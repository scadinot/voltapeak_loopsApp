//
//  SignalProcessing.swift
//  voltapeak_loops
//
//  Détection de pic et helpers de traitement du signal.
//  Reprise à l'identique de scadinot/voltapeakApp.
//

import Foundation

enum SignalProcessing {

    /// Détecte le pic (maximum) du signal avec exclusion de marges et filtre de pente.
    static func detectPeak(
        signal: [Double],
        potentials: [Double],
        marginRatio: Double = 0.10,
        maxSlope: Double? = 500
    ) -> (potential: Double, current: Double) {
        let n = signal.count
        let margin = Int(Double(n) * marginRatio)

        let searchRegion = Array(signal[margin..<(n-margin)])
        let potentialsRegion = Array(potentials[margin..<(n-margin)])

        var peakIndex = 0

        if let maxSlope = maxSlope {
            let slopes = gradient(searchRegion, x: potentialsRegion)
            var validIndices: [Int] = []
            for i in 0..<slopes.count {
                if abs(slopes[i]) < maxSlope {
                    validIndices.append(i)
                }
            }
            if validIndices.isEmpty {
                peakIndex = 0
            } else {
                var maxValue = -Double.infinity
                for idx in validIndices {
                    if searchRegion[idx] > maxValue {
                        maxValue = searchRegion[idx]
                        peakIndex = idx
                    }
                }
            }
        } else {
            if let maxIdx = searchRegion.enumerated().max(by: { $0.element < $1.element })?.offset {
                peakIndex = maxIdx
            }
        }

        let actualIndex = peakIndex + margin
        return (potentials[actualIndex], signal[actualIndex])
    }

    /// Gradient (dérivée numérique) reproduisant `numpy.gradient(y, x)` :
    /// bords en différences finies 1er ordre, intérieur en différences centrées
    /// 2e ordre pour pas non-uniformes.
    static func gradient(_ y: [Double], x: [Double]) -> [Double] {
        var grad = [Double](repeating: 0, count: y.count)
        let n = y.count
        for i in 0..<n {
            if i == 0 {
                grad[i] = (y[1] - y[0]) / (x[1] - x[0])
            } else if i == n - 1 {
                grad[i] = (y[i] - y[i-1]) / (x[i] - x[i-1])
            } else {
                let hd = x[i] - x[i-1]
                let hs = x[i+1] - x[i]
                let a = -hs / (hd * (hd + hs))
                let b = (hs - hd) / (hd * hs)
                let c = hd / (hs * (hd + hs))
                grad[i] = a * y[i-1] + b * y[i] + c * y[i+1]
            }
        }
        return grad
    }
}
