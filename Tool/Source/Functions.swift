//
//  Functions.swift
//  POET
//
//  Created by Oliver Drobnik on 08.11.16.
//  Copyright © 2016 Cocoanetics. All rights reserved.
//

import Foundation

/// POEditor uses older codes for Chinese
func xCodeLocaleFromPOEditorCode(code: String) -> String
{
	var tmpCode = code
	
	if tmpCode == "zh-CN"
	{
		tmpCode = "zh-Hans"
	}
	else if tmpCode == "zh-TW"
	{
		tmpCode = "zh-Hant"
	}
	
	let locale = Locale(identifier: tmpCode)
	return locale.identifier
}

/// The corrected strings file name to write output to
func stringsFileName(for context: String) -> String?
{
	let fileExt = (context as NSString).pathExtension
	let name = ((context as NSString).lastPathComponent as NSString).deletingPathExtension
	
	guard ["strings", "storyboard", "plist"].contains(fileExt) else
	{
		return nil
	}
	
	if fileExt == "plist"
	{
		return name + "Plist.strings"
	}
	
	return name + ".strings"
}

/// The file extension for the export format
func fileExtension(for format: POEditor.ExportFileType) -> String
{
	switch format
	{
		case .android_strings, .apple_strings:
			return "strings"
		
		case .key_value_json:
			return "json"
		
		default:
			return format.rawValue
	}
}

func exportFolderURL(settings: Settings) -> URL
{
	// determine output folder: default, relative or absolute
	
	var exportFolderURL: URL
	let outputFolder = settings.outputFolder ?? "POEditor"
	
	if outputFolder.hasPrefix("/")
	{
		exportFolderURL = URL(fileURLWithPath: outputFolder)
	}
	else
	{
		let workingDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		exportFolderURL = workingDirURL.appendingPathComponent(outputFolder, isDirectory: true)
	}
	
	return exportFolderURL
}

func processJSON(data: Data, outputFolderList: [URL]) throws
{
	// code json
	let translations = try JSONSerialization.jsonObject(with: data, options: []) as? [JSONDictionary]
	
	var contexts = [String: [Translation]]()
	
	for translation in translations ?? []
	{
		guard let term = translation["term"] as? String,
			var context = translation["context"] as? String else
		{
			preconditionFailure()
		}
  
        if context.isEmpty {
            context = "Localizable.strings"
        } else {
            let range = context.range(of: "/", options: String.CompareOptions.backwards, range: nil, locale: nil)
            if let range = range {
                context = context.substring(from: range.upperBound)
            }
        }
		
		let translated: TranslatedTerm
		
		if let single = translation["definition"] as? String
		{
			translated = TranslatedTerm.hasDefinition(single)
		}
		else if let plurals = translation["definition"] as? [String: String]
		{
			translated = TranslatedTerm.hasPlurals(plurals)
		}
		else
		{
			translated = TranslatedTerm.notTranslated
		}
		
		let comment = translation["comment"] as? String
		let trans = Translation(comment: comment, term: term, translated: translated)
		
		if var existingTrans = contexts[context]
		{
			existingTrans.append(trans)
			contexts[context] = existingTrans
		}
		else
		{
			contexts[context] = [trans]
		}
	}
	
	for key in contexts.keys.sorted()
	{
		guard let translations = contexts[key],
			   let name = stringsFileName(for: key) else { continue }
		
        for outputUrl in outputFolderList {
		    try translations.writeFile(name: name, to: outputUrl)
        }
	}
}

func export(with settings: Settings, format: POEditor.ExportFileType = .json, forXcode: Bool = true)
{
	let exportURL = exportFolderURL(settings: settings)
	
	let langStr = (settings.languages.count == 1) ? "One language" : String(format: "%ld languages", settings.languages.count)
	
	print("\(langStr) will be exported to " + exportURL.path + "\n")
	
	let fileManager = FileManager.default
	
	for code in settings.languages.sorted()
	{
		let xcode = xCodeLocaleFromPOEditorCode(code: code)
		
		print("\nExporting " + Locale(identifier: "en").localizedString(forIdentifier: xcode)! + " [" + xcode + "]...")
		
		var outputFolderList: [URL] = [exportURL.appendingPathComponent(xcode + ".lproj", isDirectory: true)]
        
        if let mapping = settings.mapping {
            if let map = mapping[xcode] {
                outputFolderList.removeAll()
                
                let languages = map.joined(separator: ", ")
                print("Language is mapped, creating: " + languages)
                
                for language in map {
                    let languageURL = exportURL.appendingPathComponent(language + ".lproj", isDirectory: true)
                    outputFolderList.append(languageURL)
                }
            }
        }
  
		do {
			if !fileManager.fileExists(atPath: exportURL.path) {
                if let firstURL = outputFolderList.first {
				    try fileManager.createDirectory(at: firstURL, withIntermediateDirectories: true, attributes: nil)
                }
			}
		} catch {
            if let firstURL = outputFolderList.first {
			    print("Unable to create output folder " + firstURL.absoluteString)
            }
			exit(1)
		}
		
		var exportError: Error?
		
		poeditor.exportProjectTranslation(projectID: settings.projectID, languageCode: code, type: format) { (result) in
			
			switch result
			{
			case .success(let url):
				
				do
				{
					let data = try Data(contentsOf: url)
					
					if forXcode
					{
						try processJSON(data: data, outputFolderList: outputFolderList)
					}
					else
					{
						let ext = fileExtension(for: format)
						let outputFileURL = exportURL.appendingPathComponent(xcode).appendingPathExtension(ext)
						
						let name = outputFileURL.lastPathComponent
						try data.write(to: outputFileURL)
						
						print("\t✓ " + name)
					}
				}
				catch let error
				{
					exportError = error
				}
				
			case .failure(let error):
				exportError = error
			}
			sema.signal()
		}
		
		sema.wait()
		
		if let error = exportError
		{
			print("\nExport Failed:" + error.localizedDescription)
			exit(1)
		}
	}
	
	print("\nExport complete\n\n")
}

