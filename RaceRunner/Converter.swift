//
//  Converter.swift
//  RaceRunner
//
//  Created by Joshua Adams on 3/17/15.
//  Copyright (c) 2015 Josh Adams. All rights reserved.
//

import Foundation

class Converter {
  fileprivate static let feetInMeter: Double = 3.281
  fileprivate static let fahrenheitMultiplier: Float = 9.0 / 5.0
  fileprivate static let celsiusFraction: Float = 5.0 / 9.0
  fileprivate static let fahrenheitAmountToAdd: Float = 32.0
  fileprivate static let celsiusMultiplier: Float = 1.0
  fileprivate static let celsiusAmountToAdd: Float = 0.0
  fileprivate static let altitudeFudge: Double = 5.0
  fileprivate static let secondsPerMinute: Int = 60
  fileprivate static let minutesPerHour: Int = 60
  fileprivate static let secondsPerHour: Int = 3600
  fileprivate static let netCaloriesPerKiloPerMeter = 0.00086139598517
  fileprivate static let totalCaloriesPerKiloPerMeter = 0.00102547141092
  fileprivate static let fahrenheitAbbr: String = "F"
  fileprivate static let celsiusAbbr: String = "C"
  fileprivate static let mileAbbr: String = "mi"
  fileprivate static let kilometerAbbr: String = "km"
  fileprivate static let feetAbbr: String = "ft"
  fileprivate static let metersAbbr: String = "m"
  fileprivate static let feet: String = "feet"
  fileprivate static let meters: String = "meters"
  fileprivate static let mile: String = "mile"
  fileprivate static let kilometer: String = "kilometer"
  fileprivate static let miles: String = "miles"
  fileprivate static let kilometers: String = "kilometers"
  static let metersInMile: Double = 1609.344
  static let metersInKilometer: Double = 1000.0
  static let kilometersPerMile: Float = 1.609344
  static let poundsPerKilogram = 2.2
  
  class func netCaloriesAsString(_ distance: Double, weight: Double) -> String {
    return String(format: "%.0f Cal", weight * distance * netCaloriesPerKiloPerMeter)
  }
  
  class func totalCaloriesAsString(_ distance: Double, weight: Double) -> String {
    return String(format: "%.0f Cal", weight * distance * totalCaloriesPerKiloPerMeter)
  }
  
  class func announceProgress(_ totalSeconds: Int, lastSeconds: Int, totalDistance: Double, lastDistance: Double, newAltitude: Double, oldAltitude: Double) {
    let totalLongDistance = convertMetersToLongDistance(totalDistance)
    var roundedDistance = NSString(format: "%.2f", totalLongDistance) as String
    if roundedDistance.characters.last! == "0" {
      roundedDistance = roundedDistance.substring(to: roundedDistance.characters.index(before: roundedDistance.endIndex))
    }
    var progressString = "total distance \(roundedDistance) \(pluralizedCurrentLongUnit(totalLongDistance)), total time \(stringifySecondCount(totalSeconds, useLongFormat: true)), split pace"
    let distanceDelta = totalDistance - lastDistance
    let secondsDelta = totalSeconds - lastSeconds
    progressString += stringifyPace(distanceDelta, seconds: secondsDelta, forSpeaking: true)
    let altitudeDelta = newAltitude - oldAltitude
    if altitudeDelta > 0.0 + altitudeFudge {
      progressString += ", gained \(stringifyAltitude(altitudeDelta, unabbreviated: true))"
    }
    else if altitudeDelta < 0.0 - altitudeFudge {
      progressString += ", lost \(stringifyAltitude(-altitudeDelta, unabbreviated: true)))"
    }
    else {
      progressString += ", no altitude change"
    }
    Utterer.utter(progressString)
  }
  
  class func pluralizedCurrentLongUnit(_ value: Double) -> String {
    switch SettingsManager.getUnitType() {
    case .Imperial:
      if value <= 1.0 {
        return mile
      }
      else {
        return miles
      }
    case .Metric:
      if value <= 1.0 {
        return kilometer
      }
      else {
        return kilometers
      }
    }
  }

  class func convertLongDistanceToMeters(_ longDistance: Double) -> Double {
    switch SettingsManager.getUnitType() {
    case .Imperial:
      return longDistance * metersInMile
    case .Metric:
      return longDistance * metersInKilometer
    }
  }

  class func convertMetersToLongDistance(_ meters: Double) -> Double {
    switch SettingsManager.getUnitType() {
    case .Imperial:
      return meters / metersInMile
    case .Metric:
      return meters / metersInKilometer
    }
  }
  
  class func stringifyKilometers(_ kilometers: Float, includeUnits: Bool = false) -> String {
    var number = kilometers
    var units = ""
    if SettingsManager.getUnitType() == .Metric {
      units = Converter.kilometerAbbr
    }
    else {
      units = Converter.mileAbbr
      number /= kilometersPerMile
    }
    var output = String(format: "%.0f", number)
    if includeUnits {
      output += " " + units
    }
    return output
  }
  
  class func floatifyMileage(_ mileage: String) -> Float {
    if SettingsManager.getUnitType() == .Metric {
      return Float(mileage)!
    }
    else {
      return Float(mileage)! * Converter.kilometersPerMile
    }
  }
  
  class func getCurrentLongUnitName() -> String {
    return SettingsManager.getUnitType() == .Imperial ? "mile" : "kilometer"
  }

  class func getCurrentAbbreviatedLongUnitName() -> String {
    return SettingsManager.getUnitType() == .Imperial ? "mile" : "km"
  }
  
  class func getCurrentPluralLongUnitName() -> String {
    return SettingsManager.getUnitType() == .Imperial ? "miles" : "kms"
  }
  
  class func convertFahrenheitToCelsius(_ temperature: Float) -> Float {
    return celsiusFraction * (temperature - fahrenheitAmountToAdd)
  }
  
  class func stringifyDistance(_ meters: Double) -> String {
    var unitDivider: Double
    var unitName: String
    if SettingsManager.getUnitType() == .Metric {
      unitName = kilometerAbbr
      unitDivider = metersInKilometer
    }
    else {
      unitName = mileAbbr
      unitDivider = metersInMile
    }
    return NSString(format: "%.2f %@", meters / unitDivider, unitName) as String
  }
  
  class func stringifySecondCount(_ seconds: Int, useLongFormat: Bool, useLongUnits: Bool = false) -> String {
    var remainingSeconds = seconds
    let hours = remainingSeconds / secondsPerHour
    remainingSeconds -= hours * secondsPerHour
    let minutes = remainingSeconds / secondsPerMinute
    remainingSeconds -= minutes * secondsPerMinute
    if useLongFormat {
      if useLongUnits {
        if hours > 0 {
          return NSString(format: "%d hour %d minutes %d seconds", hours, minutes, remainingSeconds) as String
        } else if minutes > 0 {
          return NSString(format: "%d minutes %d seconds", minutes, remainingSeconds) as String
        } else {
          return NSString(format: "%d seconds", remainingSeconds) as String
        }
      }
      else {
        if hours > 0 {
          return NSString(format: "%d hr %d min %d sec", hours, minutes, remainingSeconds) as String
        } else if minutes > 0 {
          return NSString(format: "%d min %d sec", minutes, remainingSeconds) as String
        } else {
          return NSString(format: "%d sec", remainingSeconds) as String
        }
      }
    }
    else {
      if hours > 0 {
        return NSString(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) as String
      } else if minutes > 0 {
        return NSString(format: "%d:%02d", minutes, remainingSeconds) as String
      } else {
        return NSString(format: "%d", remainingSeconds) as String
      }
    }
  }
  
  class func stringifyPace(_ meters: Double, seconds:Int, forSpeaking:Bool = false, includeUnit: Bool = true) -> String {
    if seconds == 0 || meters == 0.0 {
      return "0"
    }
    
    let avgPaceSecMeters = Double(seconds) / meters
    var unitMultiplier: Double
    var unitName: String
    if forSpeaking {
      if SettingsManager.getUnitType() == .Metric {
        unitName = getCurrentLongUnitName()
        unitMultiplier = metersInKilometer
      }
      else {
        unitName = getCurrentLongUnitName()
        unitMultiplier = metersInMile
      }
    }
    else {
      if SettingsManager.getUnitType() == .Metric {
        unitName = "min/" + kilometerAbbr
        unitMultiplier = metersInKilometer
      }
      else {
        unitName = "min/" + mileAbbr
        unitMultiplier = metersInMile
      }
    }
    let paceMin = Int((avgPaceSecMeters * unitMultiplier) / Double(secondsPerMinute))
    let paceSec = Int(avgPaceSecMeters * unitMultiplier - Double((paceMin * secondsPerMinute)))
    if !includeUnit {
      unitName = ""
    }
    if forSpeaking {
      return NSString(format: "%d minutes %02d seconds per %@", paceMin, paceSec, unitName) as String
    }
    else {
      return NSString(format: "%d:%02d %@", paceMin, paceSec, unitName) as String
    }
  }

  class func stringifyAltitude(_ meters: Double, unabbreviated: Bool = false, includeUnit: Bool = true) -> String {
    var unitMultiplier: Double
    var unitName: String
    if SettingsManager.getUnitType() == .Metric {
      unitMultiplier = 1.0
      if !unabbreviated {
        unitName = metersAbbr
      }
      else {
        unitName = Converter.meters
      }
    }
    else {
      unitMultiplier = feetInMeter
      if !unabbreviated {
        unitName = feetAbbr
      }
      else {
        unitName = feet
      }
    }
    if !includeUnit {
      unitName = ""
    }
    return NSString(format: "%.0f %@", meters * unitMultiplier, unitName) as String
  }
  
  class func stringifyTemperature(_ temperature: Float) -> String {
    var unitName: String
    var multiplier: Float
    var amountToAdd: Float
    if SettingsManager.getUnitType() == .Metric {
      unitName = celsiusAbbr
      multiplier = celsiusMultiplier
      amountToAdd = celsiusAmountToAdd
    }
    else {
      unitName = fahrenheitAbbr
      multiplier = fahrenheitMultiplier
      amountToAdd = fahrenheitAmountToAdd
    }
    return NSString(format: "%.0f° %@", temperature * multiplier + amountToAdd, unitName) as String
  }
}
