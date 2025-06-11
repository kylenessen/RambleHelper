//
//  DeviceNamesViewController.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Cocoa
import SwiftUI

class DeviceNamesViewController: NSViewController {
    private var configurationManager: ConfigurationManager
    private var tableView: NSTableView!
    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var resetButton: NSButton!
    
    init(configurationManager: ConfigurationManager) {
        self.configurationManager = configurationManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        setupUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Configure Device Names"
        refreshTable()
    }
    
    private func setupUI() {
        // Title label
        let titleLabel = NSTextField(labelWithString: "Device Names to Monitor:")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // Subtitle label
        let subtitleLabel = NSTextField(labelWithString: "RambleHelper will transfer files from devices containing these names:")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)
        
        // Table view
        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.allowsEmptySelection = true
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DeviceName"))
        column.title = "Device Name"
        column.isEditable = true
        tableView.addTableColumn(column)
        
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        // Buttons
        addButton = NSButton(title: "Add", target: self, action: #selector(addDeviceName))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)
        
        removeButton = NSButton(title: "Remove", target: self, action: #selector(removeDeviceName))
        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(removeButton)
        
        resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resetButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -16),
            
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            removeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            
            resetButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    @objc private func addDeviceName() {
        let alert = NSAlert()
        alert.messageText = "Add Device Name"
        alert.informativeText = "Enter a device name to monitor (e.g., DJI, RODE, ZOOM):"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "Device name"
        alert.accessoryView = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let deviceName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !deviceName.isEmpty {
                configurationManager.addDeviceName(deviceName)
                refreshTable()
            }
        }
    }
    
    @objc private func removeDeviceName() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < configurationManager.deviceNames.count else { return }
        
        let deviceName = configurationManager.deviceNames[selectedRow]
        configurationManager.removeDeviceName(deviceName)
        refreshTable()
    }
    
    @objc private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset Device Names"
        alert.informativeText = "This will restore the default device names (DJI, RODE, ZOOM, MIC, RECORDER). Continue?"
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            configurationManager.resetDeviceNames()
            refreshTable()
        }
    }
    
    private func refreshTable() {
        tableView.reloadData()
        removeButton.isEnabled = !configurationManager.deviceNames.isEmpty
    }
}

extension DeviceNamesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return configurationManager.deviceNames.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < configurationManager.deviceNames.count else { return nil }
        return configurationManager.deviceNames[row]
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let newName = object as? String,
              row < configurationManager.deviceNames.count else { return }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let oldName = configurationManager.deviceNames[row]
            configurationManager.removeDeviceName(oldName)
            configurationManager.addDeviceName(trimmedName)
            refreshTable()
        }
    }
}

extension DeviceNamesViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = tableView.selectedRow >= 0
    }
}