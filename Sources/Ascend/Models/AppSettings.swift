import Foundation
import SwiftData

@Model
final class AppSettings {
    var targetNetWorth: Double = 25_000
    var monthlyNetIncome: Double = 0
    var maxMonthlyExpenses: Double = 0
    var projectionHorizonMonths: Int = 60
    /// The combined return the investments are aiming to beat, as a fraction.
    var investmentReturnTarget: Double = 0.03

    init(targetNetWorth: Double = 25_000, monthlyNetIncome: Double = 0,
         maxMonthlyExpenses: Double = 0, projectionHorizonMonths: Int = 60,
         investmentReturnTarget: Double = 0.03) {
        self.targetNetWorth = targetNetWorth
        self.monthlyNetIncome = monthlyNetIncome
        self.maxMonthlyExpenses = maxMonthlyExpenses
        self.projectionHorizonMonths = projectionHorizonMonths
        self.investmentReturnTarget = investmentReturnTarget
    }
}
