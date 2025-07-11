//
//  NotificationService.swift
//  TestNotificationExtension
//
//  Created by Jordan Howlett on 7/10/25.
//

import UserNotifications
import Intents
import UIKit

class NotificationService: UNNotificationServiceExtension {

		var contentHandler: ((UNNotificationContent) -> Void)?
		var bestAttemptContent: UNMutableNotificationContent?

		override init() {
				super.init()
				NSLog("🔔 NotificationService: Extension initialized successfully!")
		}

		override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
				NSLog("🔔 NotificationService: ============== EXTENSION TRIGGERED ==============")
				NSLog("🔔 NotificationService: didReceive called with identifier: %@", request.identifier)
				NSLog("🔔 NotificationService: Original title: %@", request.content.title)
				NSLog("🔔 NotificationService: Original body: %@", request.content.body)
				NSLog("🔔 NotificationService: UserInfo: %@", request.content.userInfo)
				NSLog("🔔 NotificationService: CategoryIdentifier: %@", request.content.categoryIdentifier ?? "nil")

				// Check if this should trigger mutable content processing
				if let aps = request.content.userInfo["aps"] as? [String: Any],
					 let mutableContent = aps["mutable-content"] as? Int {
						NSLog("🔔 NotificationService: mutable-content flag: %d", mutableContent)
				} else {
						NSLog("🔔 NotificationService: WARNING - No mutable-content flag found!")
				}

				self.contentHandler = contentHandler
				bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

				guard let bestAttemptContent = bestAttemptContent else {
						NSLog("🔔 NotificationService: ERROR - bestAttemptContent is nil")
						contentHandler(request.content)
						return
				}

				// Check if we should process as communication notification
				if shouldProcessAsCommunicationNotification(request: request) {
						processCommunicationNotification(content: bestAttemptContent, originalRequest: request)
				} else {
						NSLog("🔔 NotificationService: Not processing as communication notification")
						contentHandler(bestAttemptContent)
				}
		}

		private func shouldProcessAsCommunicationNotification(request: UNNotificationRequest) -> Bool {
				// Check if we have required communication data
				// First check the body object (Expo structure)
				if let body = request.content.userInfo["body"] as? [String: Any],
					 let senderID = body["senderId"] as? String,
					 !senderID.isEmpty {
						NSLog("🔔 NotificationService: Found senderId in body: %@", senderID)
				} else if let senderID = request.content.userInfo["sender_id"] as? String,
							!senderID.isEmpty {
						NSLog("🔔 NotificationService: Found sender_id in root: %@", senderID)
				} else {
						NSLog("🔔 NotificationService: Missing sender_id/senderId, skipping communication notification")
						return false
				}

				// Check for mutable-content flag
				if let aps = request.content.userInfo["aps"] as? [String: Any],
					 let mutableContent = aps["mutable-content"] as? Int,
					 mutableContent == 1 {
						return true
				}

				return false
		}

		private func processCommunicationNotification(content: UNMutableNotificationContent, originalRequest: UNNotificationRequest) {
				NSLog("🔔 NotificationService: Creating communication notification")

				// Extract sender info from payload
				// First check the body object (Expo structure)
				var senderName: String
				var senderID: String
				var conversationID: String

				if let body = originalRequest.content.userInfo["body"] as? [String: Any] {
						senderName = body["senderName"] as? String ?? "Unknown Sender"
						senderID = body["senderId"] as? String ?? "unknown-user-id"
						conversationID = body["conversationId"] as? String ?? "unknown-conversation"
				} else {
						// Fallback to root level
						senderName = originalRequest.content.userInfo["sender_name"] as? String ?? "Unknown Sender"
						senderID = originalRequest.content.userInfo["sender_id"] as? String ?? "unknown-user-id"
						conversationID = originalRequest.content.userInfo["conversation_id"] as? String ?? "unknown-conversation"
				}

				// Create sender person with proper name components
				let handle = INPersonHandle(value: senderID, type: .unknown)

				// Create name components for better display
				var personNameComponents = PersonNameComponents()
				let nameComponents = senderName.components(separatedBy: " ")
				if nameComponents.count > 1 {
						personNameComponents.givenName = nameComponents[0]
						personNameComponents.familyName = nameComponents.dropFirst().joined(separator: " ")
				} else {
						personNameComponents.nickname = senderName
				}

				// Create sender image
				let senderImage = createSenderImage(for: senderName)
				let inImage = INImage(imageData: senderImage.pngData()!)
				NSLog("🔔 NotificationService: Created sender image for: %@", senderName)

				let senderPerson = INPerson(
						personHandle: handle,
						nameComponents: personNameComponents,
						displayName: senderName,
						image: inImage,
						contactIdentifier: nil,
						customIdentifier: senderID,
						isMe: false,
						suggestionType: .none
				)

				// Create recipient (current user)
				let meHandle = INPersonHandle(value: "current-user", type: .unknown)
				let mePerson = INPerson(
						personHandle: meHandle,
						nameComponents: nil,
						displayName: nil,
						image: nil,
						contactIdentifier: nil,
						customIdentifier: "current-user",
						isMe: true,
						suggestionType: .none
				)

				NSLog("🔔 NotificationService: Created sender: %@ and recipient", senderPerson.displayName ?? "nil")

				// Create the message intent
				let intent = INSendMessageIntent(
						recipients: [mePerson],
						outgoingMessageType: .outgoingMessageText,
						content: content.body,
						speakableGroupName: nil,
						conversationIdentifier: conversationID,
						serviceName: nil,
						sender: senderPerson,
						attachments: nil
				)

				// Set image for sender parameter
				intent.setImage(inImage, forParameterNamed: \.sender)
				NSLog("🔔 NotificationService: Created INSendMessageIntent with image")

				// Create and donate interaction
				let interaction = INInteraction(intent: intent, response: nil)
				interaction.direction = .incoming
				NSLog("🔔 NotificationService: Created interaction, donating...")

				// Donate interaction first
				interaction.donate { [weak self] error in
						if let error = error {
								NSLog("🔔 NotificationService: Donation failed: %@", error.localizedDescription)
								self?.fallbackToRegularNotification(content: content, originalRequest: originalRequest)
						} else {
								NSLog("🔔 NotificationService: Donation successful, updating content")
								self?.updateNotificationContent(content: content, intent: intent, originalRequest: originalRequest)
						}
				}
		}

		private func updateNotificationContent(content: UNMutableNotificationContent, intent: INSendMessageIntent, originalRequest: UNNotificationRequest) {
				do {
						NSLog("🔔 NotificationService: Attempting to update content from intent")
						let updatedContent = try content.updating(from: intent)
						NSLog("🔔 NotificationService: Content updated successfully")

						guard let mutableContent = updatedContent.mutableCopy() as? UNMutableNotificationContent else {
								NSLog("🔔 NotificationService: ERROR - Could not create mutable content")
								fallbackToRegularNotification(content: content, originalRequest: originalRequest)
								return
						}

						// Set thread identifier for grouping
						mutableContent.threadIdentifier = originalRequest.content.userInfo["conversation_id"] as? String ?? "default-conversation"

						// Preserve original userInfo
						mutableContent.userInfo = originalRequest.content.userInfo

						// Set category identifier for actions
						mutableContent.categoryIdentifier = "MESSAGE_CATEGORY"

						// Set sound if not already set
						if mutableContent.sound == nil {
								mutableContent.sound = .default
						}

						// Remove the mutable-content flag to avoid confusion
						if var userInfo = mutableContent.userInfo as? [String: Any] {
								if var aps = userInfo["aps"] as? [String: Any] {
										aps.removeValue(forKey: "mutable-content")
										userInfo["aps"] = aps
										mutableContent.userInfo = userInfo
								}
						}

						NSLog("🔔 NotificationService: Final title: %@", mutableContent.title)
						NSLog("🔔 NotificationService: Final body: %@", mutableContent.body)
						NSLog("🔔 NotificationService: Thread identifier: %@", mutableContent.threadIdentifier ?? "nil")
						NSLog("🔔 NotificationService: Category identifier: %@", mutableContent.categoryIdentifier ?? "nil")

						contentHandler?(mutableContent)
				} catch {
						NSLog("🔔 NotificationService: ERROR updating content: %@", error.localizedDescription)
						fallbackToRegularNotification(content: content, originalRequest: originalRequest)
				}
		}

		private func fallbackToRegularNotification(content: UNMutableNotificationContent, originalRequest: UNNotificationRequest) {
				NSLog("🔔 NotificationService: Falling back to regular notification")

				// Set basic content
				content.title = content.title.isEmpty ? "New Message" : content.title
				content.body = content.body.isEmpty ? "You have a new message" : content.body
				content.sound = .default
				content.categoryIdentifier = "MESSAGE_CATEGORY"

				// Set thread identifier for grouping
				content.threadIdentifier = originalRequest.content.userInfo["conversation_id"] as? String ?? "default-conversation"

				// Preserve userInfo
				content.userInfo = originalRequest.content.userInfo

				contentHandler?(content)
		}

		override func serviceExtensionTimeWillExpire() {
				NSLog("🔔 NotificationService: serviceExtensionTimeWillExpire called")
				// Called just before the extension will be terminated by the system.
				// Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
				if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
						NSLog("🔔 NotificationService: Delivering best attempt content due to timeout")
						// Ensure we have basic content
						if bestAttemptContent.title.isEmpty {
								bestAttemptContent.title = "New Message"
						}
						if bestAttemptContent.body.isEmpty {
								bestAttemptContent.body = "You have a new message"
						}
						bestAttemptContent.sound = .default
						contentHandler(bestAttemptContent)
				}
		}

		private func createSenderImage(for senderName: String) -> UIImage {
				NSLog("🔔 NotificationService: Creating sender image for: %@", senderName)
				let size = CGSize(width: 60, height: 60)
				let renderer = UIGraphicsImageRenderer(size: size)

				let image = renderer.image { context in
						// Create a circular background with different colors based on sender name
						let colors: [UIColor] = [.systemBlue, .systemPurple, .systemGreen, .systemOrange, .systemRed, .systemTeal, .systemIndigo]
						let colorIndex = abs(senderName.hashValue) % colors.count
						colors[colorIndex].setFill()
						context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))

						// Add initials
						let initials = extractInitials(from: senderName)
						let font = UIFont.systemFont(ofSize: 24, weight: .medium)
						let attributes: [NSAttributedString.Key: Any] = [
								.font: font,
								.foregroundColor: UIColor.white
						]

						let textSize = initials.size(withAttributes: attributes)
						let textRect = CGRect(
								x: (size.width - textSize.width) / 2,
								y: (size.height - textSize.height) / 2,
								width: textSize.width,
								height: textSize.height
						)

						initials.draw(in: textRect, withAttributes: attributes)
				}

				NSLog("🔔 NotificationService: Created image with size: %@", NSCoder.string(for: image.size))
				return image
		}

		private func extractInitials(from name: String) -> String {
				let words = name.components(separatedBy: .whitespacesAndNewlines)
						.filter { !$0.isEmpty }

				if words.count >= 2 {
						return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
				} else if let firstWord = words.first {
						return String(firstWord.prefix(2)).uppercased()
				} else {
						return "?"
				}
		}
}
