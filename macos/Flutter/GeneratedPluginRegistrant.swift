//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import open_file_mac
import path_provider_foundation
import pdf_render
import printing

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  OpenFilePlugin.register(with: registry.registrar(forPlugin: "OpenFilePlugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
  SwiftPdfRenderPlugin.register(with: registry.registrar(forPlugin: "SwiftPdfRenderPlugin"))
  PrintingPlugin.register(with: registry.registrar(forPlugin: "PrintingPlugin"))
}
