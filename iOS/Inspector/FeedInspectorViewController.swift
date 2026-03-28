//
//  FeedInspectorViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 11/6/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SafariServices
import UserNotifications
import RSCore
import Account

final class FeedInspectorViewController: UITableViewController {

	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 600.0)

	var feed: Feed!

	@IBOutlet var nameTextField: UITextField!
	@IBOutlet var newArticleNotificationsEnabledSwitch: UISwitch!
	@IBOutlet var readerViewAlwaysEnabledSwitch: UISwitch!
	@IBOutlet var homePageLabel: InteractiveLabel!
	@IBOutlet var feedURLLabel: InteractiveLabel!

	private var headerView: InspectorIconHeaderView?
	private var iconImage: IconImage? {
		return IconImageCache.shared.imageForFeed(feed)
	}

	private let homePageIndexPath = IndexPath(row: 0, section: 1)

	private var shouldHideHomePageSection: Bool {
		return feed.homePageURL == nil
	}

	private var authorizationStatus: UNAuthorizationStatus?

	// Category filter section is the last section in the storyboard + 1
	private var categoryFilterSectionIndex: Int {
		// The storyboard has sections: 0 (name/notifications/reader), 1 (homepage), 2 (feed URL)
		// We add category filter as section 3
		return 3
	}

	override func viewDidLoad() {
		tableView.register(InspectorIconHeaderView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")

		navigationItem.title = feed.nameForDisplay
		nameTextField.text = feed.nameForDisplay

		newArticleNotificationsEnabledSwitch.setOn(feed.newArticleNotificationsEnabled, animated: false)

		readerViewAlwaysEnabledSwitch.setOn(feed.readerViewAlwaysEnabled, animated: false)

		homePageLabel.text = feed.homePageURL
		feedURLLabel.text = feed.url

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(updateNotificationSettings), name: UIApplication.willEnterForegroundNotification, object: nil)

	}

	override func viewDidAppear(_ animated: Bool) {
		updateNotificationSettings()
	}

	override func viewDidDisappear(_ animated: Bool) {
		if nameTextField.text != feed.nameForDisplay {
			let nameText = nameTextField.text ?? ""
			let newName = nameText.isEmpty ? (feed.name ?? NSLocalizedString("Untitled", comment: "Feed name")) : nameText
			feed.rename(to: newName) { _ in }
		}
	}

	// MARK: Notifications
	@objc func feedIconDidBecomeAvailable(_ notification: Notification) {
		headerView?.iconView.iconImage = iconImage
	}

	@IBAction func newArticleNotificationsEnabledChanged(_ sender: Any) {
		guard let authorizationStatus else {
			newArticleNotificationsEnabledSwitch.isOn = !newArticleNotificationsEnabledSwitch.isOn
			return
		}
		if authorizationStatus == .denied {
			newArticleNotificationsEnabledSwitch.isOn = !newArticleNotificationsEnabledSwitch.isOn
			present(notificationUpdateErrorAlert(), animated: true, completion: nil)
		} else if authorizationStatus == .authorized {
			feed.newArticleNotificationsEnabled = newArticleNotificationsEnabledSwitch.isOn
		} else {
			UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
				Task { @MainActor in
					self.updateNotificationSettings()
					if granted {
						self.feed.newArticleNotificationsEnabled = self.newArticleNotificationsEnabledSwitch.isOn
						UIApplication.shared.registerForRemoteNotifications()
					} else {
						self.newArticleNotificationsEnabledSwitch.isOn = !self.newArticleNotificationsEnabledSwitch.isOn
					}
				}
			}
		}
	}

	@IBAction func readerViewAlwaysEnabledChanged(_ sender: Any) {
		feed.readerViewAlwaysEnabled = readerViewAlwaysEnabledSwitch.isOn
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	/// Returns a new indexPath, taking into consideration any
	/// conditions that may require the tableView to be
	/// displayed differently than what is setup in the storyboard.
	private func shift(_ indexPath: IndexPath) -> IndexPath {
		return IndexPath(row: indexPath.row, section: shift(indexPath.section))
	}

	/// Returns a new section, taking into consideration any
	/// conditions that may require the tableView to be
	/// displayed differently than what is setup in the storyboard.
	private func shift(_ section: Int) -> Int {
		if section >= homePageIndexPath.section && shouldHideHomePageSection {
			return section + 1
		}
		return section
	}

	/// Reverse shift: from storyboard section to displayed section.
	private func unshift(_ storyboardSection: Int) -> Int {
		if shouldHideHomePageSection && storyboardSection > homePageIndexPath.section {
			return storyboardSection - 1
		}
		return storyboardSection
	}
}

// MARK: Table View

extension FeedInspectorViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		let storyboardSections = super.numberOfSections(in: tableView)
		let baseSections = shouldHideHomePageSection ? storyboardSections - 1 : storyboardSections
		return baseSections + 1 // +1 for the category filter section
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if section == displayedFilterSection {
			// Category filter section: type picker + terms field
			return 2
		}
		return super.tableView(tableView, numberOfRowsInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if section == displayedFilterSection {
			return UITableView.automaticDimension
		}
		return section == 0 ? ImageHeaderView.rowHeight : super.tableView(tableView, heightForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if indexPath.section == displayedFilterSection {
			return UITableView.automaticDimension
		}
		return super.tableView(tableView, heightForRowAt: shift(indexPath))
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if indexPath.section == displayedFilterSection {
			return categoryFilterCell(for: indexPath.row)
		}
		let cell = super.tableView(tableView, cellForRowAt: shift(indexPath))
		if indexPath.section == 0 && indexPath.row == 1 {
			guard let label = cell.contentView.subviews.filter({ $0.isKind(of: UILabel.self) })[0] as? UILabel else {
				return cell
			}
			label.numberOfLines = 2
			label.text = feed.notificationDisplayName.capitalized
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if section == displayedFilterSection {
			return NSLocalizedString("Category Filter", comment: "Category filter section header")
		}
		return super.tableView(tableView, titleForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if section == displayedFilterSection {
			return nil // Use default header with title
		}
		if shift(section) == 0 {
			headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader") as? InspectorIconHeaderView
			headerView?.iconView.iconImage = iconImage
			return headerView
		} else {
			return super.tableView(tableView, viewForHeaderInSection: shift(section))
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let displayedFilterSection = unshift(categoryFilterSectionIndex)
		if indexPath.section == displayedFilterSection {
			if indexPath.row == 0 {
				showCategoryFilterTypePicker()
			}
			tableView.deselectRow(at: indexPath, animated: true)
			return
		}
		if shift(indexPath) == homePageIndexPath,
			let homePageUrlString = feed.homePageURL,
			let homePageUrl = URL(string: homePageUrlString) {

			let safari = SFSafariViewController(url: homePageUrl)
			safari.modalPresentationStyle = .pageSheet
			present(safari, animated: true) {
				tableView.deselectRow(at: indexPath, animated: true)
			}
		}
	}

	override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
		return 0
	}
}

// MARK: UITextFieldDelegate

extension FeedInspectorViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}

	func textFieldDidEndEditing(_ textField: UITextField) {
		if textField.tag == 1001 {
			// Category filter terms field
			let newTerms = textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
			feed.categoryFilterTerms = newTerms.isEmpty ? nil : newTerms
		}
	}

}

// MARK: UNUserNotificationCenter

extension FeedInspectorViewController {

	@objc func updateNotificationSettings() {
		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			let updatedAuthorizationStatus = settings.authorizationStatus
			DispatchQueue.main.async {
				self.authorizationStatus = updatedAuthorizationStatus
				if self.authorizationStatus == .authorized {
					UIApplication.shared.registerForRemoteNotifications()
				}
			}
		}
	}

	func notificationUpdateErrorAlert() -> UIAlertController {
		let alert = UIAlertController(title: NSLocalizedString("Enable Notifications", comment: "Notifications"),
									  message: NSLocalizedString("Notifications need to be enabled in the Settings app.", comment: "Notifications need to be enabled in the Settings app."), preferredStyle: .alert)
		let openSettings = UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Open Settings"), style: .default) { _ in
			UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false], completionHandler: nil)
		}
		let dismiss = UIAlertAction(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil)
		alert.addAction(openSettings)
		alert.addAction(dismiss)
		alert.preferredAction = openSettings
		return alert
	}

}

// MARK: - Category Filter

private extension FeedInspectorViewController {

	static let filterTypeNames = [
		NSLocalizedString("None", comment: "Category filter type: no filtering"),
		NSLocalizedString("Include only", comment: "Category filter type: include only matching"),
		NSLocalizedString("Exclude", comment: "Category filter type: exclude matching")
	]

	func categoryFilterCell(for row: Int) -> UITableViewCell {
		if row == 0 {
			return categoryFilterTypeCell()
		} else {
			return categoryFilterTermsCell()
		}
	}

	func categoryFilterTypeCell() -> UITableViewCell {
		let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
		var config = cell.defaultContentConfiguration()
		config.text = NSLocalizedString("Filter Type", comment: "Category filter type row")
		config.secondaryText = Self.filterTypeNames[feed.categoryFilterType]
		cell.contentConfiguration = config
		cell.accessoryType = .disclosureIndicator
		return cell
	}

	func categoryFilterTermsCell() -> UITableViewCell {
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
		cell.selectionStyle = .none

		let textField = UITextField()
		textField.tag = 1001
		textField.placeholder = NSLocalizedString("e.g. space, Podcast, AI", comment: "Category filter terms placeholder")
		textField.text = feed.categoryFilterTerms
		textField.delegate = self
		textField.returnKeyType = .done
		textField.font = .preferredFont(forTextStyle: .body)
		textField.translatesAutoresizingMaskIntoConstraints = false
		textField.autocapitalizationType = .none
		textField.autocorrectionType = .no

		cell.contentView.addSubview(textField)
		NSLayoutConstraint.activate([
			textField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
			textField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
			textField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
			textField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
		])

		// Hide terms field when filter is disabled
		if feed.categoryFilterType == 0 {
			cell.isHidden = true
			cell.clipsToBounds = true
		}

		return cell
	}

	func showCategoryFilterTypePicker() {
		let alert = UIAlertController(title: NSLocalizedString("Category Filter", comment: "Category filter picker title"), message: nil, preferredStyle: .actionSheet)

		for (index, name) in Self.filterTypeNames.enumerated() {
			let action = UIAlertAction(title: name, style: .default) { [weak self] _ in
				guard let self else {
					return
				}
				self.feed.categoryFilterType = index
				self.tableView.reloadData()
			}
			if index == feed.categoryFilterType {
				action.setValue(true, forKey: "checked")
			}
			alert.addAction(action)
		}

		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))

		if let popover = alert.popoverPresentationController {
			let displayedFilterSection = unshift(categoryFilterSectionIndex)
			if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: displayedFilterSection)) {
				popover.sourceView = cell
				popover.sourceRect = cell.bounds
			}
		}

		present(alert, animated: true)
	}
}
