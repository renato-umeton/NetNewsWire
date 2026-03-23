//
//  FeedInspectorViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 1/20/18.
//  Copyright © 2018 Ranchero Software. All rights reserved.
//

import AppKit
import UserNotifications
import Synchronization
import Articles
import Account

final class FeedInspectorViewController: NSViewController, Inspector {
	@IBOutlet var iconView: IconView!
	@IBOutlet var nameTextField: NSTextField?
	@IBOutlet var homePageURLTextField: NSTextField?
	@IBOutlet var urlTextField: NSTextField?
	@IBOutlet var newArticleNotificationsEnabledCheckBox: NSButton!
	@IBOutlet var readerViewAlwaysEnabledCheckBox: NSButton?

	private var categoryFilterLabel: NSTextField?
	private var categoryFilterPopUp: NSPopUpButton?
	private var categoryFilterTermsLabel: NSTextField?
	private var categoryFilterTermsField: NSTextField?

	private var feed: Feed? {
		didSet {
			if feed != oldValue {
				updateUI()
			}
		}
	}

	private var authorizationStatus: UNAuthorizationStatus?

	// MARK: Inspector

	let isFallbackInspector = false
	var objects: [Any]? {
		didSet {
			renameFeedIfNecessary()
			updateFeed()
		}
	}
	var windowTitle: String = NSLocalizedString("Feed Inspector", comment: "Feed Inspector window title")

	func canInspect(_ objects: [Any]) -> Bool {
		return objects.count == 1 && objects.first is Feed
	}

	// MARK: NSViewController

	override func viewDidLoad() {
		setupCategoryFilterUI()
		updateUI()
		NotificationCenter.default.addObserver(self, selector: #selector(imageDidBecomeAvailable(_:)), name: .imageDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: .DidUpdateFeedPreferencesFromContextMenu, object: nil)
	}

	override func viewDidAppear() {
		updateNotificationSettings()
	}

	override func viewDidDisappear() {
		renameFeedIfNecessary()
		saveCategoryFilterTermsIfNecessary()
	}

	// MARK: Actions
	@IBAction func newArticleNotificationsEnabledChanged(_ sender: Any) {
		guard authorizationStatus != nil else {
			DispatchQueue.main.async {
				self.newArticleNotificationsEnabledCheckBox.setNextState()
			}
			return
		}

		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			Task { @MainActor in
				self.updateNotificationSettings()
			}

			if settings.authorizationStatus == .denied {
				DispatchQueue.main.async {
					self.newArticleNotificationsEnabledCheckBox.setNextState()
					self.showNotificationsDeniedError()
				}
			} else if settings.authorizationStatus == .authorized {
				DispatchQueue.main.async {
					self.feed?.newArticleNotificationsEnabled = (self.newArticleNotificationsEnabledCheckBox?.state ?? .off) == .on ? true : false
				}
			} else {
				UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
					Task { @MainActor in
						self.updateNotificationSettings()
						if granted {
							DispatchQueue.main.async {
								self.feed?.newArticleNotificationsEnabled = (self.newArticleNotificationsEnabledCheckBox?.state ?? .off) == .on ? true : false
								NSApplication.shared.registerForRemoteNotifications()
							}
						} else {
							DispatchQueue.main.async {
								self.newArticleNotificationsEnabledCheckBox.setNextState()
							}
						}
					}
				}
			}
		}
	}

	@IBAction func readerViewAlwaysEnabledChanged(_ sender: Any) {
		feed?.readerViewAlwaysEnabled = (readerViewAlwaysEnabledCheckBox?.state ?? .off) == .on ? true : false
	}

	// MARK: Notifications

	@objc func imageDidBecomeAvailable(_ note: Notification) {
		updateImage()
	}
}

extension FeedInspectorViewController: NSTextFieldDelegate {

	func controlTextDidEndEditing(_ note: Notification) {
		if let textField = note.object as? NSTextField, textField === categoryFilterTermsField {
			saveCategoryFilterTermsIfNecessary()
		} else {
			renameFeedIfNecessary()
		}
	}
}

private extension FeedInspectorViewController {

	func updateFeed() {
		guard let objects = objects, objects.count == 1, let singleFeed = objects.first as? Feed else {
			feed = nil
			return
		}
		feed = singleFeed
	}

	@objc func updateUI() {
		updateImage()
		updateName()
		updateHomePageURL()
		updateFeedURL()
		updateNewArticleNotificationsEnabled()
		updateReaderViewAlwaysEnabled()
		updateCategoryFilter()
		windowTitle = feed?.nameForDisplay ?? NSLocalizedString("Feed Inspector", comment: "Feed Inspector window title")
		readerViewAlwaysEnabledCheckBox?.isEnabled = true
		view.needsLayout = true
	}

	func updateImage() {
		guard let feed = feed, let iconView = iconView else {
			return
		}
		iconView.iconImage = IconImageCache.shared.imageForFeed(feed)
	}

	func updateName() {
		guard let nameTextField = nameTextField else {
			return
		}

		let name = feed?.editedName ?? feed?.name ?? ""
		if nameTextField.stringValue != name {
			nameTextField.stringValue = name
		}
	}

	func updateHomePageURL() {
		homePageURLTextField?.stringValue = feed?.homePageURL ?? ""
	}

	func updateFeedURL() {
		urlTextField?.stringValue = feed?.url ?? ""
	}

	func updateNewArticleNotificationsEnabled() {
		newArticleNotificationsEnabledCheckBox?.title = feed?.notificationDisplayName ?? NSLocalizedString("Show notifications for new articles", comment: "Show notifications for new articles")
		newArticleNotificationsEnabledCheckBox?.state = (feed?.newArticleNotificationsEnabled ?? false) ? .on : .off
	}

	func updateReaderViewAlwaysEnabled() {
		readerViewAlwaysEnabledCheckBox?.state = (feed?.readerViewAlwaysEnabled ?? false) ? .on : .off
	}

	func updateNotificationSettings() {
		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			let authorizationStatus = settings.authorizationStatus
			Task { @MainActor in
				self.authorizationStatus = authorizationStatus
				if self.authorizationStatus == .authorized {
					NSApplication.shared.registerForRemoteNotifications()
				}
			}
		}
	}

	func showNotificationsDeniedError() {
		let updateAlert = NSAlert()
		updateAlert.alertStyle = .informational
		updateAlert.messageText = NSLocalizedString("Enable Notifications", comment: "Notifications")
		updateAlert.informativeText = NSLocalizedString("To enable notifications, open Notifications in System Preferences, then find NetNewsWire in the list.", comment: "To enable notifications, open Notifications in System Preferences, then find NetNewsWire in the list.")
		updateAlert.addButton(withTitle: NSLocalizedString("Open System Preferences", comment: "Open System Preferences"))
		updateAlert.addButton(withTitle: NSLocalizedString("Close", comment: "Close"))
		let modalResponse = updateAlert.runModal()
		if modalResponse == .alertFirstButtonReturn {
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
		}
	}

	func renameFeedIfNecessary() {
		guard let nameTextField else {
			return
		}
		let newName = nameTextField.stringValue.trimmingWhitespace
		guard !newName.isEmpty else {
			return
		}
		guard let feed, let account = feed.account, feed.nameForDisplay != newName else {
			return
		}

		Task { @MainActor in
			do {
				try await account.renameFeed(feed, name: newName)
				windowTitle = feed.nameForDisplay
			} catch {
				presentError(error)
			}
		}
	}

	// MARK: - Category Filter UI

	func setupCategoryFilterUI() {
		guard let readerViewCheckBox = readerViewAlwaysEnabledCheckBox else {
			return
		}

		let separator = NSBox()
		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(separator)

		let label = NSTextField(labelWithString: NSLocalizedString("Category Filter:", comment: "Category filter label in feed inspector"))
		label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
		label.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(label)
		categoryFilterLabel = label

		let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
		popUp.translatesAutoresizingMaskIntoConstraints = false
		popUp.addItems(withTitles: [
			NSLocalizedString("None", comment: "Category filter type: no filtering"),
			NSLocalizedString("Include only", comment: "Category filter type: include only matching"),
			NSLocalizedString("Exclude", comment: "Category filter type: exclude matching")
		])
		popUp.target = self
		popUp.action = #selector(categoryFilterTypeChanged(_:))
		view.addSubview(popUp)
		categoryFilterPopUp = popUp

		let termsLabel = NSTextField(labelWithString: NSLocalizedString("Categories (comma-separated):", comment: "Category filter terms label"))
		termsLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		termsLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(termsLabel)
		categoryFilterTermsLabel = termsLabel

		let termsField = NSTextField()
		termsField.translatesAutoresizingMaskIntoConstraints = false
		termsField.placeholderString = NSLocalizedString("e.g. space, Podcast, AI", comment: "Category filter terms placeholder")
		termsField.delegate = self
		termsField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		view.addSubview(termsField)
		categoryFilterTermsField = termsField

		NSLayoutConstraint.activate([
			separator.topAnchor.constraint(equalTo: readerViewCheckBox.bottomAnchor, constant: 12),
			separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

			label.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
			label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

			popUp.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
			popUp.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
			popUp.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

			termsLabel.topAnchor.constraint(equalTo: popUp.bottomAnchor, constant: 8),
			termsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

			termsField.topAnchor.constraint(equalTo: termsLabel.bottomAnchor, constant: 4),
			termsField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			termsField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
		])
	}

	@objc func categoryFilterTypeChanged(_ sender: NSPopUpButton) {
		feed?.categoryFilterType = sender.indexOfSelectedItem
		updateCategoryFilterFieldsVisibility()
	}

	func updateCategoryFilter() {
		let filterType = feed?.categoryFilterType ?? 0
		categoryFilterPopUp?.selectItem(at: filterType)
		categoryFilterTermsField?.stringValue = feed?.categoryFilterTerms ?? ""
		updateCategoryFilterFieldsVisibility()
	}

	func updateCategoryFilterFieldsVisibility() {
		let isEnabled = (categoryFilterPopUp?.indexOfSelectedItem ?? 0) != 0
		categoryFilterTermsLabel?.isHidden = !isEnabled
		categoryFilterTermsField?.isHidden = !isEnabled
	}

	func saveCategoryFilterTermsIfNecessary() {
		guard let termsField = categoryFilterTermsField else {
			return
		}
		let newTerms = termsField.stringValue.trimmingCharacters(in: .whitespaces)
		let currentTerms = feed?.categoryFilterTerms ?? ""
		if newTerms != currentTerms {
			feed?.categoryFilterTerms = newTerms.isEmpty ? nil : newTerms
		}
	}
}
