//
//  RunModel.swift
//  RaceRunner
//
//  Created by Joshua Adams on 3/13/15.
//  Copyright (c) 2015 Josh Adams. All rights reserved.
//

import Foundation
import MapKit
import CoreLocation
import CoreData
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


protocol ImportedRunDelegate {
  func runWasImported()
}

class RunModel: NSObject, CLLocationManagerDelegate, PubNubPublisher {
  var locations: [CLLocation]! = []
  var status : Status = .preRun
  var runDelegate: RunDelegate?
  var importedRunDelegate: ImportedRunDelegate?
  var run: Run!
  var totalDistance = 0.0
  fileprivate var currentAltitude = 0.0
  fileprivate var oldSplitAltitude = 0.0
  fileprivate var currentSplitDistance = 0.0
  fileprivate var totalSeconds = 0
  fileprivate var shouldReportSplits = false
  fileprivate var lastDistance = 0.0
  fileprivate var lastSeconds = 0
  fileprivate var reportEvery = SettingsManager.never
  fileprivate var temperature: Float = 0.0
  fileprivate var weather = ""
  fileprivate var timer: Timer!
  fileprivate var initialLocation: CLLocation!
  fileprivate var locationManager: LocationManager!
  fileprivate var autoName = Run.noAutoName
  fileprivate var didSetAutoNameAndFirstLoc = false
  fileprivate var altGained  = 0.0
  fileprivate var altLost = 0.0
  fileprivate var minLong = 0.0
  fileprivate var maxLong = 0.0
  fileprivate var minLat = 0.0
  fileprivate var maxLat = 0.0
  fileprivate var minAlt = 0.0
  fileprivate var maxAlt = 0.0
  fileprivate var curAlt = 0.0
  fileprivate var runToSimulate: Run!
  fileprivate var gpxFile: String!
  fileprivate var secondLength = 1.0
  fileprivate var spectatorStoppedRun = false
  fileprivate (set) var sortedAltitudes: [Double] = []
  fileprivate (set) var sortedPaces: [Double] = []
  static let altFudge: Double = 0.1
  static let minDistance = 400.0
  fileprivate static let distanceTolerance: Double = 0.05
  fileprivate static let coordinateTolerance: Double = 0.0000050
  fileprivate static let minAccuracy: CLLocationDistance = 20.0
  fileprivate static let distanceFilter: CLLocationDistance = 10.0
  fileprivate static let freezeDriedAccuracy: CLLocationAccuracy = 5.0
  fileprivate static let defaultTemperature: Float = 25.0
  fileprivate static let defaultWeather = "sunny"
  fileprivate static let importSucceededMessage = "Successfully imported run"
  fileprivate static let importFailedMessage = "Run import failed."
  fileprivate static let importRunTitle = "Import Run"
  fileprivate static let ok = "OK"
  
  enum Status {
    case preRun
    case inProgress
    case paused
  }
  
  static let runModel = RunModel()
      
  class func initializeRunModelWithGpxFile(_ gpxFile: String) {
    runModel.gpxFile = gpxFile
    runModel.runToSimulate = nil
    runModel.locationManager = LocationManager(gpxFile: gpxFile)
    finishSimulatorSetup()
  }
  
  class func initializeRunModelWithRun(_ run: Run) {
    runModel.runToSimulate = run
    runModel.gpxFile = nil
    var cLLocations: [CLLocation] = []
    for uncastedLocation in run.locations {
      let location = uncastedLocation as! Location
      cLLocations.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: location.latitude.doubleValue, longitude: location.longitude.doubleValue), altitude: location.altitude.doubleValue, horizontalAccuracy: RunModel.freezeDriedAccuracy, verticalAccuracy: RunModel.freezeDriedAccuracy, timestamp: location.timestamp as Date))
    }
    runModel.locationManager = LocationManager(locations: cLLocations)
    finishSimulatorSetup()
  }
  
  class func registerForImportedRunNotifications(_ importedRunDelegate: ImportedRunDelegate) {
    runModel.importedRunDelegate = importedRunDelegate
  }
  
  class func deregisterForImportedRunNotifications() {
    runModel.importedRunDelegate = nil
  }
  
  class func finishSimulatorSetup() {
    runModel.secondLength /= SettingsManager.getMultiplier()
    runModel.locationManager.secondLength = runModel.secondLength
    runModel.status = .preRun
    configureLocationManager()
    runModel.locationManager.startUpdatingLocation()
  }
  
  class func initializeRunModel() {
    runModel.runToSimulate = nil
    runModel.gpxFile = nil
    runModel.secondLength = 1.0
    if runModel.locationManager == nil {
      runModel.locationManager = LocationManager()
      configureLocationManager()
    }
    runModel.locationManager.startUpdatingLocation()
  }
  
  class func configureLocationManager() {
    runModel.locationManager.delegate = runModel
    runModel.locationManager.desiredAccuracy = kCLLocationAccuracyBest
    runModel.locationManager.distanceFilter = kCLDistanceFilterNone // This is the default, but explicit is good.
    runModel.locationManager.activityType = .fitness
    runModel.locationManager.requestAlwaysAuthorization()
    runModel.locationManager.distanceFilter = RunModel.distanceFilter
    runModel.locationManager.pausesLocationUpdatesAutomatically = false
    runModel.locationManager.allowsBackgroundLocationUpdates = true
    runModel.locationManager.startUpdatingLocation()
  }
  
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    switch status {
    case .preRun:
      initialLocation = locations[0]
      runDelegate?.showInitialCoordinate(initialLocation.coordinate)
      locationManager?.stopUpdatingLocation()
      if runToSimulate == nil && gpxFile == nil {
        DarkSky().currentWeather(CLLocationCoordinate2D(
          latitude: initialLocation.coordinate.latitude,
          longitude: initialLocation.coordinate.longitude) ) { result in
            switch result {
            case .Error(_, _):
              self.temperature = Run.noTemperature
              self.weather = Run.noWeather
            case .success(_, let dictionary):
              let currently = dictionary?["currently"] as! NSDictionary
              self.temperature = Converter.convertFahrenheitToCelsius(currently["apparentTemperature"] as! Float)
              self.weather = currently["summary"] as! String
            }
          }
      }
    case .inProgress:
      for location in locations {
        let newLocation: CLLocation = location
        if abs(newLocation.horizontalAccuracy) < RunModel.minAccuracy {
          if self.locations.count > 0 {
            let altitudeIndex = sortedAltitudes.insertionIndexOf(newLocation.altitude) { $0 < $1 }
            sortedAltitudes.insert(newLocation.altitude, at: altitudeIndex)
            let altitudeColor = UiHelpers.colorForValue(newLocation.altitude, sortedArray: sortedAltitudes, index: altitudeIndex)
            let distanceDelta = newLocation.distance(from: self.locations.last!)
            totalDistance += distanceDelta
            let timeDelta = newLocation.timestamp.timeIntervalSince(self.locations.last!.timestamp)
            let pace = distanceDelta / timeDelta
            let paceIndex = sortedPaces.insertionIndexOf(pace) { $0 < $1 }
            sortedPaces.insert(pace, at: paceIndex)
            let paceColor = UiHelpers.colorForValue(pace, sortedArray: sortedPaces, index: paceIndex)
            runDelegate?.plotToCoordinate(newLocation.coordinate, altitudeColor: altitudeColor, paceColor: paceColor)
          }
          else {
            runDelegate?.showInitialCoordinate(newLocation.coordinate)
          }
          self.locations.append(newLocation)
        }
        
        if !didSetAutoNameAndFirstLoc {
          didSetAutoNameAndFirstLoc = true
          if runToSimulate == nil && gpxFile == nil {
            CLGeocoder().reverseGeocodeLocation(newLocation, completionHandler: {(placemarks, error) in
              if error == nil {
                if placemarks?.count > 0 {
                  let placemark = placemarks![0]
                  if let thoroughfare = placemark.thoroughfare {
                    self.autoName = thoroughfare
                  }
                }
                else {
                  self.autoName = Run.noAutoName
                }
              }
              else {
                self.autoName = Run.noAutoName
              }
            })
          }
          oldSplitAltitude = newLocation.altitude
          minAlt = newLocation.altitude
          maxAlt = newLocation.altitude
          minLong = newLocation.coordinate.longitude
          maxLong = newLocation.coordinate.longitude
          minLat = newLocation.coordinate.latitude
          maxLat = newLocation.coordinate.latitude
        }
        else {
          if newLocation.coordinate.latitude < minLat {
            minLat = newLocation.coordinate.latitude
          }
          if newLocation.coordinate.longitude < minLong {
            minLong = newLocation.coordinate.longitude
          }
          if newLocation.coordinate.latitude > maxLat {
            maxLat = newLocation.coordinate.latitude
          }
          if newLocation.coordinate.longitude > maxLong {
            maxLong = newLocation.coordinate.longitude
          }
          if newLocation.altitude < minAlt {
            minAlt = newLocation.altitude
          }
          if newLocation.altitude > maxAlt {
            maxAlt = newLocation.altitude
          }
          if newLocation.altitude > curAlt + RunModel.altFudge {
            altGained += newLocation.altitude - curAlt
          }
          if newLocation.altitude < curAlt - RunModel.altFudge {
            altLost += curAlt - newLocation.altitude
          }
        }
        curAlt = newLocation.altitude
      }
    case .paused:
      break
    }
  }
  
  func eachSecond() {
    if status == .inProgress {
      totalSeconds += 1
      if SettingsManager.getBroadcastNextRun() && locations.count > 0 && SettingsManager.getRealRunInProgress() {
        PubNubManager.publishLocation(locations[locations.count - 1], distance: totalDistance, seconds: totalSeconds, publisher: SettingsManager.getBroadcastName())
      }
      runDelegate?.receiveProgress(totalDistance, totalSeconds: totalSeconds, altitude: curAlt, altGained: altGained, altLost: altLost)
      currentSplitDistance = totalDistance - lastDistance
      if shouldReportSplits && currentSplitDistance >= reportEvery {
        currentSplitDistance -= reportEvery
        if (SettingsManager.getAudibleSplits()) {
          Converter.announceProgress(totalSeconds, lastSeconds: lastSeconds, totalDistance: totalDistance, lastDistance: lastDistance, newAltitude: curAlt, oldAltitude: oldSplitAltitude)
        }
        lastDistance = totalDistance
        lastSeconds = totalSeconds
        oldSplitAltitude = curAlt
      }
    }
  }
  
  static func loadStateAndStart() {
    //let fetchRequest = NSFetchRequest()
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RunInProgress")
    let context = CDManager.sharedCDManager.context
    fetchRequest.entity = NSEntityDescription.entity(forEntityName: "RunInProgress", in: context!)
    let runInProgress = ((try? context!.fetch(fetchRequest)) as! [RunInProgress])[0]
    var savedLocations = [CLLocation]()
    for location in runInProgress.tempLocations {
      let savedLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: (location as AnyObject).latitude.doubleValue, longitude:
        (location as AnyObject).longitude.doubleValue), altitude: (location as AnyObject).altitude.doubleValue, horizontalAccuracy: freezeDriedAccuracy, verticalAccuracy: freezeDriedAccuracy, timestamp: (location as AnyObject).timestamp)
      savedLocations.append(savedLocation)
    }
    initializeRunModel()
    runModel.start(locations: savedLocations, oldSplitAltitude: runInProgress.oldSplitAltitude.doubleValue, totalSeconds: Int(runInProgress.totalSeconds.int32Value), lastSeconds: Int(runInProgress.lastSeconds.int32Value), totalDistance: runInProgress.totalDistance.doubleValue, lastDistance: runInProgress.lastDistance.doubleValue, currentAltitude: runInProgress.currentAltitude.doubleValue, currentSplitDistance: runInProgress.currentSplitDistance.doubleValue, altGained: runInProgress.altGained.doubleValue, altLost: runInProgress.altLost.doubleValue, maxLong: runInProgress.maxLong.doubleValue, minLong: runInProgress.minLong.doubleValue, maxLat: runInProgress.maxLat.doubleValue, minLat: runInProgress.minLat.doubleValue, maxAlt: runInProgress.maxAlt.doubleValue, minAlt: runInProgress.minAlt.doubleValue)
    context!.delete(runInProgress)
    CDManager.saveContext()
  }
  
  
  static func saveState() {
    let runInProgress: RunInProgress = NSEntityDescription.insertNewObject(forEntityName: "RunInProgress", into: CDManager.sharedCDManager.context) as! RunInProgress
    runInProgress.oldSplitAltitude = NSNumber(value: runModel.oldSplitAltitude)
    runInProgress.totalSeconds = NSNumber(value: runModel.totalSeconds)
    runInProgress.lastSeconds = NSNumber(value: runModel.lastSeconds)
    runInProgress.totalDistance = NSNumber(value: runModel.totalDistance)
    runInProgress.lastDistance = NSNumber(value: runModel.lastDistance)
    runInProgress.currentAltitude = NSNumber(value: runModel.currentAltitude)
    runInProgress.currentSplitDistance = NSNumber(value: runModel.currentSplitDistance)
    runInProgress.altGained = NSNumber(value: runModel.altGained)
    runInProgress.altLost = NSNumber(value: runModel.altLost)
    runInProgress.maxLong = NSNumber(value: runModel.maxLong)
    runInProgress.minLong = NSNumber(value: runModel.minLong)
    runInProgress.maxLat = NSNumber(value: runModel.maxLat)
    runInProgress.minLat = NSNumber(value: runModel.minLat)
    runInProgress.maxAlt = NSNumber(value: runModel.maxAlt)
    runInProgress.minAlt = NSNumber(value: runModel.minAlt)
    var locationArray: [Location] = []
    for location in runModel.locations {
      let locationObject: Location = NSEntityDescription.insertNewObject(forEntityName: "Location", into: CDManager.sharedCDManager.context) as! Location
      locationObject.timestamp = location.timestamp
      locationObject.latitude = NSNumber(value: location.coordinate.latitude)
      locationObject.longitude = NSNumber(value: location.coordinate.longitude)
      locationObject.altitude = NSNumber(value: location.altitude)
      locationArray.append(locationObject)
    }
    runInProgress.tempLocations = NSOrderedSet(array: locationArray)
    CDManager.saveContext()
  }
  
  func start(locations: [CLLocation], oldSplitAltitude: Double, totalSeconds: Int, lastSeconds: Int, totalDistance: Double, lastDistance: Double, currentAltitude: Double, currentSplitDistance: Double, altGained: Double, altLost: Double, maxLong: Double, minLong: Double, maxLat: Double, minLat: Double, maxAlt: Double, minAlt: Double) {
    status = .inProgress
    reportEvery = SettingsManager.getReportEvery()
    if reportEvery == SettingsManager.never {
      shouldReportSplits = false
    }
    else {
      shouldReportSplits = true
    }

    self.locations = locations
    self.oldSplitAltitude = oldSplitAltitude
    self.totalSeconds = totalSeconds
    self.lastSeconds = lastSeconds
    self.totalDistance = totalDistance
    self.lastDistance = lastDistance
    self.currentAltitude = currentAltitude
    self.currentSplitDistance = currentSplitDistance
    self.altGained = altGained
    self.altLost = altLost
    self.maxLong = maxLong
    self.minLong = minLong
    self.maxLat = maxLat
    self.minLat = minLat
    self.maxAlt = maxAlt
    self.minAlt = minAlt
    locationManager.startUpdatingLocation()
    startTimer()
    if runToSimulate == nil && gpxFile == nil {
      SettingsManager.setRealRunInProgress(true)
    }
    if SettingsManager.getBroadcastNextRun() && SettingsManager.getRealRunInProgress() {
      PubNubManager.subscribeToChannel(self, publisher: SettingsManager.getBroadcastName())
    }
  }
  
  func start() {
    start(locations: [], oldSplitAltitude: 0.0, totalSeconds: 0, lastSeconds: 0, totalDistance: 0.0, lastDistance: 0.0, currentAltitude: 0.0, currentSplitDistance: 0.0, altGained: 0.0, altLost: 0.0, maxLong: 0.0, minLong: 0.0, maxLat: 0.0, minLat: 0.0, maxAlt: 0.0, minAlt: 0.0)
  }
  
  class func addRun(_ url: URL) -> Bool {
    var succeeded = true
    var newRun: Run?
    if let parser = GpxParser(url: url) {
      let parseResult = parser.parse()
      newRun = RunModel.addRun(parseResult.locations, autoName: parseResult.autoName, customName: parseResult.customName, timestamp: parseResult.locations.last!.timestamp, weather: parseResult.weather, temperature: parseResult.temperature, weight: parseResult.weight)
    }
    else {
      succeeded = false
    }
    if newRun == nil {
      succeeded = false
    }
    var resultMessage = ""
    if succeeded {
      if newRun?.customName == Run.noAutoName as NSString {
        resultMessage = RunModel.importSucceededMessage + "."
      }
      else {
        resultMessage = RunModel.importSucceededMessage + " " + ((newRun?.displayName())! as String) + "."
      }
      runModel.importedRunDelegate?.runWasImported()
    }
    else {
      resultMessage = RunModel.importFailedMessage
    }
    UIAlertController.showMessage(resultMessage, title: RunModel.importRunTitle)
    return succeeded
  }
  
  fileprivate class func addRun(_ coordinates: [CLLocation], customName: String, autoName: String, timestamp: Date, weather: String, temperature: Float, distance: Double, maxAltitude: Double, minAltitude: Double, maxLongitude: Double, minLongitude: Double, maxLatitude: Double, minLatitude: Double, altitudeGained: Double, altitudeLost: Double, weight: Double) -> Run {
    let newRun: Run = NSEntityDescription.insertNewObject(forEntityName: "Run", into: CDManager.sharedCDManager.context) as! Run
    newRun.distance = NSNumber(value: distance)
    newRun.duration = NSNumber(value: coordinates[coordinates.count - 1].timestamp.timeIntervalSince(coordinates[0].timestamp))
    newRun.timestamp = timestamp
    newRun.weather = weather as NSString
    newRun.temperature = NSNumber(value: temperature)
    newRun.customName = customName as NSString
    newRun.autoName = autoName as NSString
    newRun.maxAltitude = NSNumber(value: maxAltitude)
    newRun.minAltitude = NSNumber(value: minAltitude)
    newRun.maxLatitude = NSNumber(value: maxLatitude)
    newRun.minLatitude = NSNumber(value: minLatitude)
    newRun.maxLongitude = NSNumber(value: maxLongitude)
    newRun.minLongitude = NSNumber(value: minLongitude)
    newRun.altitudeGained = NSNumber(value: altitudeGained)
    newRun.altitudeLost = NSNumber(value: altitudeLost)
    newRun.weight = NSNumber(value: weight)
    var locationArray: [Location] = []
    for location in coordinates {
      let locationObject: Location = NSEntityDescription.insertNewObject(forEntityName: "Location", into: CDManager.sharedCDManager.context) as! Location
      locationObject.timestamp = location.timestamp
      locationObject.latitude = NSNumber(value: location.coordinate.latitude)
      locationObject.longitude = NSNumber(value: location.coordinate.longitude)
      locationObject.altitude = NSNumber(value: location.altitude)
      locationArray.append(locationObject)
    }
    newRun.locations = NSOrderedSet(array: locationArray)
    CDManager.saveContext()
    return newRun
  }
  
  class func setMaxAndMinAltLatLon(_ coordinates: [CLLocation]) {
    
  }
  
  class func addRun(_ coordinates: [CLLocation], autoName: String, customName: String, timestamp: Date, weather: String, temperature: Float, weight: Double) -> Run {
    var distance = 0.0
    var altGained  = 0.0
    var altLost = 0.0
    var minLong = coordinates[0].coordinate.longitude
    var maxLong = coordinates[0].coordinate.longitude
    var minLat = coordinates[0].coordinate.latitude
    var maxLat = coordinates[0].coordinate.latitude
    var minAlt = coordinates[0].altitude
    var maxAlt = coordinates[0].altitude
    var curAlt = coordinates[0].altitude
    var currentCoordinate = coordinates[0]
    for i in 1 ..< coordinates.count {
      distance += coordinates[i].distance(from: currentCoordinate)
      currentCoordinate = coordinates[i]
      if currentCoordinate.coordinate.latitude < minLat {
        minLat = currentCoordinate.coordinate.latitude
      }
      if currentCoordinate.coordinate.longitude < minLong {
        minLong = currentCoordinate.coordinate.longitude
      }
      if currentCoordinate.coordinate.latitude > maxLat {
        maxLat = currentCoordinate.coordinate.latitude
      }
      if currentCoordinate.coordinate.longitude > maxLong {
        maxLong = currentCoordinate.coordinate.longitude
      }
      if currentCoordinate.altitude < minAlt {
        minAlt = currentCoordinate.altitude
      }
      if currentCoordinate.altitude > maxAlt {
        maxAlt = currentCoordinate.altitude
      }
      if currentCoordinate.altitude > curAlt + RunModel.altFudge {
        altGained += currentCoordinate.altitude - curAlt
      }
      if currentCoordinate.altitude < curAlt - RunModel.altFudge {
        altLost += curAlt - currentCoordinate.altitude
      }
      curAlt = coordinates[i].altitude
    }
    return RunModel.addRun(coordinates, customName: customName, autoName: autoName, timestamp: timestamp, weather: weather, temperature: temperature, distance: distance, maxAltitude: maxAlt, minAltitude: minAlt, maxLongitude: maxLong, minLongitude: minLong, maxLatitude: maxLat, minLatitude: minLat, altitudeGained: altGained, altitudeLost: altLost, weight: weight)
  }
  
  class func gpsIsAvailable() -> Bool {
    if CLLocationManager.authorizationStatus() == .authorizedAlways {
      return true
    }
    else {
      return false
    }
  }
  
  static func deleteSavedRun() {
    SettingsManager.setRealRunInProgress(false)
    SettingsManager.setWarnedUserAboutLowRam(false)
    //let fetchRequest = NSFetchRequest()
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RunInProgress")
    let context = CDManager.sharedCDManager.context
    fetchRequest.entity = NSEntityDescription.entity(forEntityName: "RunInProgress", in: context!)
    do {
      let runsInProgress = (try context!.fetch(fetchRequest)) as? [RunInProgress]
      if let runsInProgress = runsInProgress {
        if runsInProgress.count > 0 {
          context!.delete(runsInProgress[0])
          CDManager.saveContext()
        }
      }
    }
    catch _ as NSError {}
  }
  
  func stop() {
    timer.invalidate()
    locationManager.stopUpdatingLocation()
    if SettingsManager.getRealRunInProgress() && SettingsManager.getBroadcastNextRun() {
      PubNubManager.runStopped()
      PubNubManager.unsubscribeFromChannel(SettingsManager.getBroadcastName())
      SettingsManager.setBroadcastNextRun(false)
    }
    if runToSimulate == nil && gpxFile == nil {
      RunModel.deleteSavedRun()
    }
    if runToSimulate == nil && gpxFile == nil && totalDistance > RunModel.minDistance {
      var customName = ""
      //let fetchRequest = NSFetchRequest()
      let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Run")
      let context = CDManager.sharedCDManager.context
      fetchRequest.entity = NSEntityDescription.entity(forEntityName: "Run", in: context!)
      let pastRuns = (try! context!.fetch(fetchRequest)) as! [Run]
      for pastRun in pastRuns {
        if pastRun.customName != "" {
          if (!RunModel.matchMeasurement(pastRun.distance.doubleValue, measurement2: totalDistance, tolerance: RunModel.distanceTolerance)) ||
              (!RunModel.matchMeasurement(pastRun.maxLatitude.doubleValue, measurement2: maxLat, tolerance: RunModel.coordinateTolerance)) ||
              (!RunModel.matchMeasurement(pastRun.minLatitude.doubleValue, measurement2: minLat, tolerance: RunModel.coordinateTolerance)) ||
              (!RunModel.matchMeasurement(pastRun.maxLongitude.doubleValue, measurement2: maxLong, tolerance: RunModel.coordinateTolerance)) ||
              (!RunModel.matchMeasurement(pastRun.minLongitude.doubleValue, measurement2: minLong, tolerance: RunModel.coordinateTolerance)) {
            continue
          }
          customName = pastRun.customName as String
          break
        }
      }
      run = RunModel.addRun(locations, customName: customName, autoName: autoName, timestamp: Date(), weather: weather, temperature: temperature, distance: totalDistance, maxAltitude: maxAlt, minAltitude: minAlt, maxLongitude: maxLong, minLongitude: minLong, maxLatitude: maxLat, minLatitude: minLat, altitudeGained: altGained, altitudeLost: altLost, weight: SettingsManager.getWeight())
      let result = Shoes.addMeters(totalDistance)
      if result != Shoes.shoesAreOkay {
        DispatchQueue.main.asyncAfter(deadline: .now() + UiConstants.messageDelay) {
          UIAlertController.showMessage(result, title: Shoes.warningTitle, okTitle: Shoes.gotIt)
        }
      }
      if spectatorStoppedRun {
        runDelegate?.stopRun()
        spectatorStoppedRun = false
      }
    }
    else {
      // I don't consider this a magic number because the unadjusted length of a second will never change.
      secondLength = 1.0
      locationManager.kill()
      locationManager = nil
    }
    totalSeconds = 0
    totalDistance = 0.0
    currentSplitDistance = 0.0
    status = .preRun
    locations = []
    didSetAutoNameAndFirstLoc = false
    altGained  = 0.0
    altLost = 0.0
    minLong = 0.0
    maxLong = 0.0
    minLat = 0.0
    maxLat = 0.0
    minAlt = 0.0
    maxAlt = 0.0
    sortedAltitudes = []
    sortedPaces = []
  }
  
  func pause() {
    status = .paused
    timer.invalidate()
    locationManager.stopUpdatingLocation()
  }
  
  func resume() {
    status = .inProgress
    locationManager.startUpdatingLocation()
    startTimer()
  }
  
  func startTimer() {
    timer = Timer.scheduledTimer(timeInterval: secondLength, target: self, selector: #selector(RunModel.eachSecond), userInfo: nil, repeats: true)
  }
  
  class func matchMeasurement(_ measurement1: Double, measurement2: Double, tolerance: Double) -> Bool {
    let diff = fabs(measurement2 - measurement1)
    if (diff / measurement2) > tolerance {
      return false
    }
    else {
      return true
    }
  }
  
  func stopRun() {
    spectatorStoppedRun = true
    stop()
  }
  
  func receiveMessage(_ message: String) {
    Utterer.utter(message)
  }
}


