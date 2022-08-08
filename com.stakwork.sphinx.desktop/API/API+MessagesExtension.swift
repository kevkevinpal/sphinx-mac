//
//  APIMessagesExtension.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

extension API {
    func sendMessage(
        params: [String: AnyObject],
        callback:@escaping MessageObjectCallback,
        errorCallback:@escaping EmptyCallback
    ) {
        
        guard let request = getURLRequest(route: "/messages", params: params as NSDictionary?, method: "POST") else {
            errorCallback()
            return
        }

        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        callback(JSON(response))
                    } else {
                        errorCallback()
                    }
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    func getMessagesPaginated(
        page: Int,
        date: Date,
        callback: @escaping GetMessagesPaginatedCallback,
        errorCallback: @escaping EmptyCallback
    ){
        
        if !ConnectivityHelper.isConnectedToInternet {
            networksConnectionLost()
            return
        }
        
        let itemsPerPage = ChatListViewModel.kMessagesPerPage
        let offset = (page - 1) * itemsPerPage
        var route = "/msgs?offset=\(offset)&limit=\(itemsPerPage)&order=desc"
        
        let dateString = (lastSeenMessagesDate ?? Date(timeIntervalSince1970: 0))
        if let dateString = dateString.getStringFromDate(format:"yyyy-MM-dd HH:mm:ss").percentEscaped {
            route = "\(route)&date=\(dateString)"
        }
        
        guard let request = getURLRequest(route: route, method: "GET") else {
            errorCallback()
            return
        }
        
        cancellableRequest(request, type: .messages) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        let newMessages = JSON(response["new_messages"] ?? []).arrayValue
                        let messagesTotal = JSON(response["new_messages_total"] ?? -1).intValue
                        
                        if ((newMessages.count > 0 || page > 1) && newMessages.count < itemsPerPage) {
                            //is last page. Date should be tracked
                            self.lastSeenMessagesDate = date
                        }
                        
                        self.cancellableRequest = nil
                        callback(messagesTotal, newMessages)
                        return
                    }
                }
                self.cancellableRequest = nil
                errorCallback()
            case .failure(_):
                self.cancellableRequest = nil
                errorCallback()
            }
        }
    }
    
    func deleteMessage(
        messageId: Int,
        callback:@escaping DeleteMessageCallback
    ) {
        
        guard let request = getURLRequest(route: "/message/\(messageId)", method: "DELETE") else {
            callback(false, JSON())
            return
        }

        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        callback(true, JSON(response))
                    } else {
                        callback(false, JSON())
                    }
                }
            case .failure(_):
                callback(false, JSON())
            }
        }
    }
    
    func sendDirectPayment(
        params: [String: AnyObject],
        callback:@escaping DirectPaymentResultsCallback,
        errorCallback:@escaping EmptyCallback
    ) {
        
        guard let request = getURLRequest(route: "/payment", params: params as NSDictionary?, method: "POST") else {
            callback(false)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let _ = json["success"] as? Bool {
                        if let response = json["response"] as? NSDictionary {
                            if let _ = response["destination_key"] as? String {
                                callback(nil)
                            } else {
                                callback(JSON(response))
                            }
                            return
                        }
                    }
                }
                errorCallback()
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    public func createInvoice(
        parameters: [String : AnyObject],
        callback: @escaping CreateInvoiceCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        
        guard let request = getURLRequest(route: "/invoices", params: parameters as NSDictionary?, method: "POST") else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        if let invoiceString = response["invoice"] as? String {
                            callback(nil, invoiceString)
                        } else {
                            callback(JSON(response), nil)
                        }
                    } else {
                        errorCallback()
                    }
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    public func payInvoice(
        parameters: [String : AnyObject],
        callback: @escaping PayInvoiceCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        
        guard let request = getURLRequest(route: "/invoices", params: parameters as NSDictionary?, method: "PUT") else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        callback(JSON(response))
                    } else {
                        errorCallback()
                    }
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    public func payLsat(
        parameters: [String : AnyObject],
        callback: @escaping PayInvoiceCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = getURLRequest(route: "/lsats", params: parameters as NSDictionary?, method: "POST") else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        callback(JSON(response))
                    } else {
                        errorCallback()
                    }
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    public func getLsat(
        issuer: String,
        paths: String,
        callback: @escaping PayInvoiceCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        print("calling the actual path", issuer, paths)
        guard let request = getURLRequest(route: "/lsats/\(issuer)/\(paths)", method: "GET") else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        callback(JSON(response))
                    } else {
                        errorCallback()
                    }
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    public func setChatMessagesAsSeen(
        chatId: Int,
        callback: @escaping SuccessCallback
    ) {
        
        guard let request = getURLRequest(route: "/messages/\(chatId)/read", method: "POST") else {
            callback(false)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, success {
                        callback(true)
                    } else {
                        callback(false)
                    }
                }
            case .failure(_):
                callback(false)
            }
        }
    }
}
