//
//  WebAppHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/08/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import WebKit

class WebAppHelper : NSObject {
    
    
    public let messageHandler = "sphinx"
    
    var webView : WKWebView! = nil
    var authorizeHandler: (([String: AnyObject]) -> ())! = nil
    
    var persistingValues: [String: AnyObject] = [:]
    
    func setWebView(_ webView: WKWebView, authorizeHandler: @escaping (([String: AnyObject]) -> ())) {
        self.webView = webView
        self.authorizeHandler = authorizeHandler
    }
}

extension WebAppHelper : WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == messageHandler {
            guard let dict = message.body as? [String: AnyObject] else {
                return
            }

            if let type = dict["type"] as? String {
                switch(type) {
                case "AUTHORIZE":
                    saveValue(dict["amount"] as AnyObject, for: "budget")
                    authorizeHandler(dict)
                    break
                case "KEYSEND":
                    sendKeySend(dict)
                    break
                case "UPDATED":
                    sendUpdatedMessage(dict)
                    NotificationCenter.default.post(name: .onBalanceDidChange, object: nil)
                    break
                case "RELOAD":
                    sendReloadMessage(dict)
                    break
                case "PAYMENT":
                    sendPayment(dict)
                    break
                case "LSAT":
                    saveLSAT(dict)
                    break
                default:
                    break
                }
            }
        }
    }
    
    func jsonStringWithObject(obj: AnyObject) -> String? {
        let jsonData  = try? JSONSerialization.data(withJSONObject: obj, options: JSONSerialization.WritingOptions(rawValue: 0))
        
        if let jsonData = jsonData {
            return String(data: jsonData, encoding: .utf8)
        }
        
        return nil
    }
    
    func sendMessage(dict: [String: AnyObject]) {
        if let string = jsonStringWithObject(obj: dict as AnyObject) {
            let javascript = "window.sphinxMessage('\(string)')"
            webView.evaluateJavaScript(javascript, completionHandler: nil)
        }
    }
    
    func setTypeApplicationAndPassword(params: inout [String: AnyObject], dict: [String: AnyObject]) {
        let password = EncryptionManager.randomString(length: 16)
        saveValue(password as AnyObject, for: "password")
        
        params["type"] = dict["type"] as AnyObject
        params["application"] = dict["application"] as AnyObject
        params["password"] = password as AnyObject
    }
    
    //AUTHORIZE
    func authorizeWebApp(amount: Int, dict: [String: AnyObject], completion: @escaping () -> ()) {
        if let challenge = dict["challenge"] as? String {
            signChallenge(amount: amount, challenge: challenge, dict: dict, completion: completion)
        } else {
            sendAuthorizeMessage(amount: amount, dict: dict, completion: completion)
        }
    }
    
    func sendAuthorizeMessage(amount: Int, signature: String? = nil, dict: [String: AnyObject], completion: @escaping () -> ()) {
        if let pubKey = UserData.sharedInstance.getUserPubKey() {
            var params: [String: AnyObject] = [:]
            setTypeApplicationAndPassword(params: &params, dict: dict)
            
            params["budget"] = amount as AnyObject
            params["pubkey"] = pubKey as AnyObject
            
            saveValue(amount as AnyObject, for: "budget")
            saveValue(pubKey as AnyObject, for: "pubkey")
            
            if let signature = signature {
                params["signature"] = signature as AnyObject
            }
            
            sendMessage(dict: params)
            completion()
        }
    }
    
    func signChallenge(amount: Int, challenge: String, dict: [String: AnyObject], completion: @escaping () -> ()) {
        API.sharedInstance.signChallenge(challenge: challenge, callback: { signature in
            self.sendAuthorizeMessage(amount: amount, signature: signature, dict: dict, completion: completion)
        })
    }
    
    //UPDATED
    func sendUpdatedMessage(_ dict: [String: AnyObject]) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        sendMessage(dict: params)
    }
    
    //RELOAD
    func sendReloadMessage(_ dict: [String: AnyObject]) {
        let (success, budget, pubKey) = getReloadParams(dict: dict)
        var params: [String: AnyObject] = [:]
        params["success"] = success as AnyObject
        params["budget"] = budget as AnyObject
        params["pubkey"] = pubKey as AnyObject
        
        setTypeApplicationAndPassword(params: &params, dict: dict)
        sendMessage(dict: params)
    }
    
    func getReloadParams(dict: [String: AnyObject]) -> (Bool, Int, String) {
        let password: String? = getValue(withKey: "password")
        var budget = 0
        var pubKey = ""
        var success = false
        
        if let pass = dict["password"] as? String, pass == password {
            let savedBudget: Int? = getValue(withKey: "budget")
            let savedPubKey: String? = getValue(withKey: "pubkey")
            
            success = true
            budget = savedBudget ?? 0
            pubKey = savedPubKey ?? ""
        }
        
        return (success, budget, pubKey)
    }
    
    //KEYSEND
    func sendKeySendResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["success"] = success as AnyObject
        
        sendMessage(dict: params)
    }
    
    func sendKeySend(_ dict: [String: AnyObject]) {
        if let dest = dict["dest"] as? String, let amt = dict["amt"] as? Int {
            let params = getParams(pubKey: dest, amount: amt)
            let canPay: DarwinBoolean = checkCanPay(amount: amt)
            if(canPay == false){
                self.sendKeySendResponse(dict: dict, success: false)
                return
            }
            API.sharedInstance.sendDirectPayment(params: params, callback: { payment in
                self.sendKeySendResponse(dict: dict, success: true)
            }, errorCallback: {
                self.sendKeySendResponse(dict: dict, success: false)
            })
        }
    }
    
    //Payment
    func sendPaymentResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["success"] = success as AnyObject
        
        sendMessage(dict: params)
    }
    
    func sendPayment(_ dict: [String: AnyObject]) {
        if let paymentRequest = dict["paymentRequest"] as? String {
            let params = ["payment_request": paymentRequest as AnyObject]
            let prDecoder = PaymentRequestDecoder()
            prDecoder.decodePaymentRequest(paymentRequest: paymentRequest)
            let amount = prDecoder.getAmount()
            if let amount = amount {
                let canPay: DarwinBoolean = checkCanPay(amount: amount)
                if(canPay == false){
                    self.sendPaymentResponse(dict: dict, success: false)
                    return
                }
                API.sharedInstance.payInvoice(parameters: params, callback: { payment in
                    self.sendPaymentResponse(dict: dict, success: true)
                }, errorCallback: {
                    self.sendPaymentResponse(dict: dict, success: false)
                })
            } else {
                self.sendPaymentResponse(dict: dict, success: false)
            }
        }
    }
    
    //Payment
    func sendLsatResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["lsat"] = dict["lsat"] as AnyObject
        params["success"] = success as AnyObject
        let savedBudget: Int? = getValue(withKey: "budget")
        if let budget = savedBudget {
            params["budget"] = budget as AnyObject
        }
        sendMessage(dict: params)
    }
    
    func saveLSAT(_ dict: [String: AnyObject]) {
        print("THIS is the dict", dict)
        if let paymentRequest = dict["paymentRequest"] as? String, let macaroon = dict["macaroon"] as? String, let issuer = dict["issuer"] as? String, let paths = dict["paths"] as? String{
            let params = ["paymentRequest": paymentRequest as AnyObject, "macaroon": macaroon as AnyObject, "issuer": issuer as AnyObject, "paths": paths as AnyObject]
            print("These are the params: ", params)

            let prDecoder = PaymentRequestDecoder()
            prDecoder.decodePaymentRequest(paymentRequest: paymentRequest)
            let amount = prDecoder.getAmount()
            if let amount = amount {
                let canPay: DarwinBoolean = checkCanPay(amount: amount)
                if(canPay == false){
                    self.sendLsatResponse(dict: dict, success: false)
                    return
                }
                let lsat = getLsatIfOwned(issuer: issuer, paths: paths, dict: dict)
                if(lsat == true) {
                    
                    return
                }
                API.sharedInstance.payLsat(parameters: params, callback: { payment in
                    var newDict = dict
                    if let lsat = payment["lsat"].string {
                        newDict["lsat"] = lsat as AnyObject
                    }
                    
                    self.sendLsatResponse(dict: newDict, success: true)
                }, errorCallback: {
                    self.sendLsatResponse(dict: dict, success: false)
                })
            }else{
                self.sendLsatResponse(dict: dict, success: false)
            }
        }
    }
    
    func getParams(pubKey: String, amount: Int) -> [String: AnyObject] {
        var parameters = [String : AnyObject]()
        parameters["amount"] = amount as AnyObject?
        parameters["destination_key"] = pubKey as AnyObject?
            
        return parameters
    }
    
    func saveValue(_ value: AnyObject, for key: String) {
        persistingValues[key] = value
    }
    
    func getValue<T>(withKey key: String) -> T? {
        if let value = persistingValues[key] as? T {
            return value
        }
        return nil
    }
    
    
    func checkCanPay(amount: Int) -> DarwinBoolean {
        let savedBudget: Int? = getValue(withKey: "budget")
        if((savedBudget ?? 0) < amount || amount == -1){
            return false
        }
        if let savedBudget = savedBudget {
            let newBudget = savedBudget - amount
            saveValue(newBudget as AnyObject, for: "budget")
            return true
        }
        return false
    }

    func getLsatIfOwned(issuer: String, paths: String, dict: [String: AnyObject]) -> DarwinBoolean {
        print("Checking if we have lsat saved", issuer, paths)
        API.sharedInstance.getLsat(issuer: issuer, paths: paths, callback: { payment in
            print("request success", payment)
            var newDict = dict
            if let lsat = payment["lsat"].string {
                newDict["lsat"] = lsat as AnyObject
            }
            
            self.sendLsatResponse(dict: newDict, success: true)
        }, errorCallback: {
            
        })
        return false
    }
    
}
