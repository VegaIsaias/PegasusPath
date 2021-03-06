//
//  PopUpViewController.swift
//  PegasusPath
//
//  Created by Christopher Donoso on 3/13/18.
//  Copyright © 2018 Christopher Donoso. All rights reserved.
//

import UIKit

class PopUpViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var nameField: UITextField!
    //@IBOutlet weak var descriptionField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.showAnimate()

        nameField.delegate = self
        //descriptionField.delegate = self
        
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //Sends out the notification broadcast
    @IBAction func closePopUp(_ sender: Any) {
        
        NotificationCenter.default.post(name: .saveNameField, object: self)
        //NotificationCenter.default.post(name: .saveDescriptionField, object: self)
        self.removeAnimate()
    }
    
    //Opens the pop up
    func showAnimate()
    {
        self.view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        self.view.alpha = 0.0;
        UIView.animate(withDuration: 0.25, animations: {
            self.view.alpha = 1.0
            self.view.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        });
    }
    
    //Closes the pop up
    func removeAnimate()
    {
        UIView.animate(withDuration: 0.25, animations: {
            self.view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            self.view.alpha = 0.0;
        }, completion:{(finished : Bool)  in
            if (finished)
            {
                self.view.removeFromSuperview()
            }
        });
    }
    
    @IBAction func cancel(_ sender: Any) {
        self.removeAnimate()
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    @IBAction func settingButtonTapped(_ sender: UIButton!) {
        
//        self.performSegue(withIdentifier: "settingSegue", sender: self)
//        self.removeAnimate()
        let storyBoard : UIStoryboard = UIStoryboard(name: "Main", bundle:nil)
        
        let nextViewController = storyBoard.instantiateViewController(withIdentifier: "LogoutController") as! LogoutController
        self.present(nextViewController, animated:true, completion:nil)
        
        self.removeAnimate()
        
    }
    
}

extension ViewController : UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

