iOS OTA Extraction Utility
==========================

[![Swift 3.0](https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![Platforms OS X](https://img.shields.io/badge/Platforms-OS%20X-lightgray.svg?style=flat)](https://developer.apple.com/swift/)
[![License Apache](https://img.shields.io/badge/License-APACHE2-blue.svg?style=flat)](https://www.apache.org/licenses/LICENSE-2.0.html)

The ota tool is a simple command-line utility to extract the file system image from an iOS over-the-air (OTA) update file. Example usage:

`$ ota 5dbe0f2561d6e651abd0c46815be5aa8ef61d163.zip ./outputDir`

Links to various update images for the iPhone can be found on [the iPhone Wiki](https://www.theiphonewiki.com/wiki/OTA_Updates/iPhone/9.x). Credits to Jonathan Levin for his [article](http://newosxbook.com/articles/OTA.html) on OTA updates, from which portions of this code is based off of.

License
-------
This project is available under the Apache 2.0 license. See LICENSE for details.