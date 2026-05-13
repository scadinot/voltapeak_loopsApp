//
//  WhittakerASPLS.swift
//  voltapeak_loops
//
//  Implémentation EXACTE de pybaselines.whittaker.aspls (Zhang 2020).
//  Reprise à l'identique de scadinot/voltapeakApp.
//
//  Note : la boucle `for _ in 0...maxIter` exécute volontairement `maxIter + 1`
//  itérations, ce qui reproduit exactement `for i in range(max_iter + 1)` de
//  pybaselines._Whittaker.aspls.
//

import Foundation

enum WhittakerASPLS {

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
        var w = weights ?? [Double](repeating: 1.0, count: n)
        var a = alpha ?? [Double](repeating: 1.0, count: n)

        let DTD = buildDTD(n: n, diffOrder: diffOrder)

        var baseline = [Double](repeating: 0.0, count: n)

        for _ in 0...maxIter {
            var A = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)
            for i in 0..<n {
                let scale = lam * a[i]
                for j in 0..<n {
                    A[i][j] = scale * DTD[i][j]
                }
                A[i][i] += w[i]
            }

            var b = [Double](repeating: 0.0, count: n)
            for i in 0..<n {
                b[i] = w[i] * y[i]
            }

            baseline = solveFallback(A: A, b: b)

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

    /// Construit D^T D directement pour diffOrder=2 (matrice pentadiagonale n×n).
    private static func buildDTD(n: Int, diffOrder: Int) -> [[Double]] {
        guard diffOrder == 2 else {
            fatalError("Seul diffOrder=2 est supporté")
        }

        var DTD = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in 0..<n {
                let dist = abs(i - j)
                if dist == 0 {
                    if i == 0 || i == n - 1 {
                        DTD[i][j] = 1.0
                    } else if i == 1 || i == n - 2 {
                        DTD[i][j] = 5.0
                    } else {
                        DTD[i][j] = 6.0
                    }
                } else if dist == 1 {
                    if (i == 0 && j == 1) || (i == 1 && j == 0) ||
                       (i == n - 1 && j == n - 2) || (i == n - 2 && j == n - 1) {
                        DTD[i][j] = -2.0
                    } else {
                        DTD[i][j] = -4.0
                    }
                } else if dist == 2 {
                    DTD[i][j] = 1.0
                }
            }
        }

        return DTD
    }

    /// Élimination de Gauss avec pivotage partiel (système non symétrique à cause de diag(α)).
    private static func solveFallback(A: [[Double]], b: [Double]) -> [Double] {
        let n = A.count
        var M = A
        var y = b

        for k in 0..<n {
            var maxRow = k
            var maxVal = abs(M[k][k])
            for i in (k+1)..<n {
                if abs(M[i][k]) > maxVal {
                    maxVal = abs(M[i][k])
                    maxRow = i
                }
            }
            if maxRow != k {
                M.swapAt(k, maxRow)
                y.swapAt(k, maxRow)
            }
            for i in (k+1)..<n {
                let factor = M[i][k] / M[k][k]
                for j in k..<n {
                    M[i][j] -= factor * M[k][j]
                }
                y[i] -= factor * y[k]
            }
        }

        var x = [Double](repeating: 0.0, count: n)
        for i in stride(from: n-1, through: 0, by: -1) {
            var sum = y[i]
            for j in (i+1)..<n {
                sum -= M[i][j] * x[j]
            }
            x[i] = sum / M[i][i]
        }
        return x
    }
}
