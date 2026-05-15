//
//  WhittakerASPLS.swift
//  voltapeak_loops
//
//  Implémentation EXACTE de pybaselines.whittaker.aspls (Zhang 2020).
//  Reprise à l'identique de scadinot/voltapeakApp.
//
//  Solveur banded LAPACK `dgbsv_` via Accelerate.framework : la matrice
//  `diag(α)·(λ·D^TD) + diag(w)` est pentadiagonale (KL=KU=2), résolue en
//  O(n) au lieu d'un Gauss dense O(n³). Aligné sur la référence canonique
//  scadinot/voltapeak_batchApp.
//
//  Note : la boucle `for _ in 0...maxIter` exécute volontairement `maxIter + 1`
//  itérations, ce qui reproduit exactement `for i in range(max_iter + 1)` de
//  pybaselines._Whittaker.aspls.
//

import Foundation
import Accelerate

enum WhittakerASPLS {

    /// Garde-fou : au-delà de cette taille, le caller DOIT refuser le fichier
    /// en amont. Filet de sécurité contre les fichiers corrompus ou mal parsés.
    static let maxN: Int = 200_000

    static func aspls(
        y: [Double],
        lam: Double = 1e5,
        diffOrder: Int = 2,
        maxIter: Int = 100,
        tol: Double = 1e-3,
        weights: [Double]? = nil,
        alpha: [Double]? = nil,
        asymmetricCoef: Double = 0.5
    ) -> [Double] {
        let n = y.count
        // Garde-fou debug-only. Les callers (`LoopsBatchProcessor.processOne`)
        // sont responsables du filtre amont qui remonte une `FileError.tooManyPoints`.
        // En Release, on laisse passer si jamais un chemin oublie le check : le
        // solveur banded reste tractable bien au-delà de `maxN`.
        assert(
            n <= maxN,
            "WhittakerASPLS.aspls: signal trop grand (\(n) > \(maxN)). Le caller doit filtrer en amont."
        )

        var w = weights ?? [Double](repeating: 1.0, count: n)
        var a = alpha ?? [Double](repeating: 1.0, count: n)

        // Format LAPACK band column-major : KL=KU=2, LDAB = 2·KL+KU+1 = 7.
        let kl = 2
        let ku = 2
        let ldab = 2 * kl + ku + 1   // 7

        let dtdBandedTemplate = buildDTDBanded(n: n, diffOrder: diffOrder, kl: kl, ku: ku, ldab: ldab)

        var baseline = [Double](repeating: 0.0, count: n)

        for _ in 0...maxIter {
            // ab = diag(α) · (λ · DTD), puis + diag(w). α multiplie la LIGNE i.
            var ab = dtdBandedTemplate
            for j in 0..<n {
                let iMin = max(0, j - ku)
                let iMax = min(n - 1, j + kl)
                for i in iMin...iMax {
                    let bandRow = kl + ku + i - j
                    ab[bandRow + j * ldab] *= lam * a[i]
                }
                ab[(kl + ku) + j * ldab] += w[j]
            }

            var b = [Double](repeating: 0.0, count: n)
            for i in 0..<n {
                b[i] = w[i] * y[i]
            }

            // Résolution banded LU avec pivotage partiel : dgbsv_
            var n_l = __LAPACK_int(n)
            var kl_l = __LAPACK_int(kl)
            var ku_l = __LAPACK_int(ku)
            var nrhs = __LAPACK_int(1)
            var ldab_l = __LAPACK_int(ldab)
            var ldb_l = __LAPACK_int(n)
            var info = __LAPACK_int(0)
            var ipiv = [__LAPACK_int](repeating: 0, count: n)

            ab.withUnsafeMutableBufferPointer { abPtr in
                b.withUnsafeMutableBufferPointer { bPtr in
                    dgbsv_(
                        &n_l, &kl_l, &ku_l, &nrhs,
                        abPtr.baseAddress, &ldab_l,
                        &ipiv,
                        bPtr.baseAddress, &ldb_l,
                        &info
                    )
                }
            }
            // info<0 = bug d'appel (argument invalide à la position -info).
            // info>0 = matrice singulière à la ligne `info` (NaN/Inf dans y, ou
            // poids/α extrêmes). Dans les deux cas, on fail-fast avec un message
            // diagnostique au lieu d'un crash opaque.
            if info < 0 {
                fatalError("dgbsv_ : argument invalide à la position \(-info) (bug d'appel interne).")
            }
            if info > 0 {
                fatalError("dgbsv_ : matrice singulière à la ligne \(info) — vérifiez NaN/Inf dans y, ou poids/α extrêmes.")
            }
            baseline = b

            var residual = [Double](repeating: 0.0, count: n)
            var maxAbsRes = 0.0
            for i in 0..<n {
                residual[i] = y[i] - baseline[i]
                let absR = abs(residual[i])
                if absR > maxAbsRes { maxAbsRes = absR }
            }

            var negRes: [Double] = []
            for r in residual where r < 0 {
                negRes.append(r)
            }
            if negRes.count < 2 { break }

            let negMean = negRes.reduce(0, +) / Double(negRes.count)
            var variance = 0.0
            for r in negRes {
                let d = r - negMean
                variance += d * d
            }
            let sigma = sqrt(variance / Double(negRes.count - 1))
            guard sigma > 0 else { break }

            var newW = [Double](repeating: 0.0, count: n)
            let kOverSigma = asymmetricCoef / sigma
            for i in 0..<n {
                newW[i] = 1.0 / (1.0 + exp(kOverSigma * (residual[i] - sigma)))
            }

            var sumDiff = 0.0
            var sumNewAbs = 0.0
            for i in 0..<n {
                sumDiff += abs(w[i] - newW[i])
                sumNewAbs += abs(newW[i])
            }
            let relDiff = sumNewAbs > 0 ? sumDiff / sumNewAbs : 0.0
            if relDiff < tol { break }

            w = newW
            if maxAbsRes > 0 {
                for i in 0..<n {
                    a[i] = abs(residual[i]) / maxAbsRes
                }
            }
        }

        return baseline
    }

    /// Construit D^T D directement en format LAPACK band column-major pour diffOrder=2.
    /// Pour les détails du stockage band, voir l'en-tête de fichier.
    private static func buildDTDBanded(
        n: Int, diffOrder: Int, kl: Int, ku: Int, ldab: Int
    ) -> [Double] {
        guard diffOrder == 2 else {
            fatalError("Seul diffOrder=2 est supporté")
        }

        var ab = [Double](repeating: 0.0, count: ldab * n)

        // Diagonale principale : 1 aux coins, 5 aux quasi-bords, 6 au centre
        for j in 0..<n {
            let v: Double
            if j == 0 || j == n - 1 {
                v = 1.0
            } else if j == 1 || j == n - 2 {
                v = 5.0
            } else {
                v = 6.0
            }
            ab[(kl + ku) + j * ldab] = v
        }

        // Super-diagonale 1 (i = j-1) : -2 aux extrémités, -4 sinon
        for j in 1..<n {
            let i = j - 1
            let v: Double = ((i == 0 && j == 1) || (i == n - 2 && j == n - 1)) ? -2.0 : -4.0
            ab[(kl + ku - 1) + j * ldab] = v
        }

        // Sub-diagonale 1 (i = j+1) : -2 aux extrémités, -4 sinon
        for j in 0..<(n - 1) {
            let i = j + 1
            let v: Double = ((i == 1 && j == 0) || (i == n - 1 && j == n - 2)) ? -2.0 : -4.0
            ab[(kl + ku + 1) + j * ldab] = v
        }

        // Super-diagonale 2 (i = j-2) : 1
        for j in 2..<n {
            ab[(kl + ku - 2) + j * ldab] = 1.0
        }

        // Sub-diagonale 2 (i = j+2) : 1
        for j in 0..<(n - 2) {
            ab[(kl + ku + 2) + j * ldab] = 1.0
        }

        return ab
    }
}
