//
//  UIAlertController+showMessage.swift
//  RaceRunner
//
//  Created by Joshua Adams on 1/12/16.
//  Copyright © 2016 Josh Adams. All rights reserved.
//

import UIKit

extension UIAlertController {
  static var okTitle: String { get { return "OK" } } // static let causes compilation error
  
  class func showMessage(message: String, title: String, okTitle: String = UIAlertController.okTitle, handler: ((UIAlertAction) -> Void)? = nil) {
    let alertController = UIAlertController(title: title, message: message, preferredStyle: UIAlertControllerStyle.Alert)
    let okAction = UIAlertAction(title: okTitle, style: UIAlertActionStyle.Default, handler: handler)
    alertController.addAction(okAction)
    alertController.view.tintColor = UiConstants.intermediate1Color
    if let topController = UIApplication.topViewController() {
      topController.presentViewController(alertController, animated: true, completion: nil)
    }
  }
}