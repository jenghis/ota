/*
 * Copyright 2016 Jenghis, LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

// NSData extensions to convert bytes
// to integer equivalents
extension NSData {
    var UInt16Value: UInt16? {
        if length == 2 {
            var value = UInt16()
            getBytes(&value, length: 2)
            return value
        }

        return nil
    }

    var UInt32Value: UInt32? {
        if length == 4 {
            var value = UInt32()
            getBytes(&value, length: 4)
            return value
        }

        return nil
    }

    var UInt64Value: UInt64? {
        if length == 8 {
            var value = UInt64()
            getBytes(&value, length: 8)
            return value
        }

        return nil
    }
}

// Create any missing folders within a path
func createIntermediateDirectoriesForFile(path: NSURL) {
    let fm = NSFileManager.defaultManager()
    if let i = path.path {
        let j = (i as NSString).stringByDeletingLastPathComponent

        do {
            try fm.createDirectoryAtPath(j, withIntermediateDirectories: true, attributes: nil)
        } catch {
            exitWithError("File manager error")
        }
    }
}

// Returns a String containing the path to a temporary
// file located within the 'ota' folder of a user's
// temporary directory
func createTemporaryFile() -> String {
    let uuid = NSUUID().UUIDString.lowercaseString
    let path = NSTemporaryDirectory().stringByAppendingString("ota/\(uuid)")

    createIntermediateDirectoriesForFile(NSURL(fileURLWithPath: path))
    NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)

    return path
}

// Removes the 'ota' folder created by the process
// inside the temporary directory
func removeTemporaryDirectory() {
    let temp = NSTemporaryDirectory().stringByAppendingString("ota")
    let tempPath = NSURL(fileURLWithPath: temp)

    do {
        try NSFileManager.defaultManager().removeItemAtURL(tempPath)
    }
    catch {
        exitWithError("File manager error")
    }
}

func handleSignal(signal: Int32)  {
    removeTemporaryDirectory()
    exit(signal)
}

func exitWithError(e: String) {
    removeTemporaryDirectory()
    print(e)
    exit(1)
}

func printUsage() {
    print("Usage: ota [input] [output dir]")
    exit(1)
}

// We are only interested in the 'payload' file within the zip container.
// Payload is stored uncompressed so locate the binary position of the payload
// and write out to disk.
func zipExtract(path: NSURL) -> NSURL? {
    print("Extracting zip file")

    // Map file to reduce memory usage
    if let file = try? NSData(contentsOfURL: path, options: .DataReadingMappedIfSafe) {
        var currentPosition = 0
        var errorFlag = false
        var range = NSMakeRange(0, 0)

        while currentPosition < file.length {
            // Compression type
            currentPosition += 8
            range = NSMakeRange(currentPosition, 2)
            let type = file.subdataWithRange(range).UInt16Value

            // Compressed file size
            currentPosition += 10
            range = NSMakeRange(currentPosition, 4)
            let compressedSize = file.subdataWithRange(range).UInt32Value

            // File name length
            currentPosition += 8
            range = NSMakeRange(currentPosition, 2)
            let nameLength = file.subdataWithRange(range).UInt16Value

            // Used only for the correct offset
            currentPosition += 2
            range = NSMakeRange(currentPosition, 2)
            let extraFieldLength = file.subdataWithRange(range).UInt16Value

            if nameLength != nil {
                // Get filename bytes
                currentPosition += 2
                range = NSMakeRange(currentPosition, Int(nameLength!))
                let nameBytes = file.subdataWithRange(range)

                currentPosition += Int(nameLength!)

                if extraFieldLength != nil {
                    currentPosition += Int(extraFieldLength!)
                }
                else {
                    errorFlag = true
                }

                if let name = String(data: nameBytes, encoding: NSUTF8StringEncoding) {
                    // Check for 'payload' filename and that the file is uncompressed
                    if name == "AssetData/payloadv2/payload" && type == UInt16(0) {
                        if compressedSize != nil {
                            let temp = createTemporaryFile()
                            let fileHandle = NSFileHandle(forWritingAtPath: temp)

                            // Write payload to disk and return
                            range = NSMakeRange(currentPosition, Int(compressedSize!))
                            fileHandle?.writeData(file.subdataWithRange(range))

                            return NSURL(fileURLWithPath: temp)
                        }
                        else {
                            errorFlag = true
                        }
                    }
                    // Skip over all other files
                    else if compressedSize != nil {
                        currentPosition += Int(compressedSize!)
                    }
                    else {
                        errorFlag = true
                    }
                }
            }
            else {
                errorFlag = true
            }

            if errorFlag {
                exitWithError("Unexpected file format")
            }
        }
    }

    return nil
}

func pbzxExtract(path: NSURL) -> NSURL? {
    // Based on pbzx file format specification by Jonathan Levin
    // Website: http://newosxbook.com/articles/OTA.html

    print("Extracting pbzx file")

    if let file = try? NSData(contentsOfURL: path, options: .DataReadingMappedIfSafe) {
        let magicBit = file.subdataWithRange(NSMakeRange(0, 4))
        if let signature = String(data: magicBit, encoding: NSUTF8StringEncoding) {
            // Check magic number to verify it is a pbzx file
            if signature != "pbzx" {
                exitWithError("Invalid file signature")
            }

            var currentPosition = 4
            var flag = UInt64?()
            var range = NSMakeRange(currentPosition, 8)

            let temp = createTemporaryFile()
            let fileHandle = NSFileHandle(forWritingAtPath: temp)

            flag = file.subdataWithRange(range).UInt64Value?.byteSwapped
            currentPosition += 8

            // Flag specifies whether more chunks are available
            while flag == 0x01000000 {
                // Next flag
                range = NSMakeRange(currentPosition, 8)
                flag = file.subdataWithRange(range).UInt64Value?.byteSwapped

                // Size of chunk in bytes
                currentPosition += sizeof(UInt64)
                range = NSMakeRange(currentPosition, 8)

                if let length = file.subdataWithRange(range).UInt64Value?.byteSwapped {
                    // Write chunk data to disk
                    currentPosition += 8
                    range = NSMakeRange(currentPosition, Int(length))
                    fileHandle?.writeData(file.subdataWithRange(range))
                    currentPosition += Int(length)
                }
            }

            // Remove input file
            do {
                try NSFileManager.defaultManager().removeItemAtURL(path)
            }
            catch {
                exitWithError("File manager error")
            }

            return NSURL(fileURLWithPath: temp)
        }
        else {
            exitWithError("Invalid file")
        }
    }
    
    return nil
}

func xzExtract(path: NSURL) -> NSURL? {
    print("Extracting xz file")

    if let file = try? NSData(contentsOfURL: path, options: .DataReadingMappedIfSafe) {
        // XZ decoder setup
        let decoder = xz_dec_init(XZ_DYNALLOC, 1 << 26)
        var buffer = xz_buf()
        xz_crc32_init()

        let bufferSize = 1024
        var inBuffer = [UInt8](count: bufferSize, repeatedValue: 0)
        let outBuffer = [UInt8](count: bufferSize, repeatedValue: 0)

        buffer.in_buf = UnsafePointer(inBuffer)
        buffer.in_pos = 0
        buffer.in_size = 0

        buffer.out_buf = UnsafeMutablePointer(outBuffer)
        buffer.out_pos = 0
        buffer.out_size = bufferSize

        let temp = createTemporaryFile()
        let fileHandle = NSFileHandle(forWritingAtPath: temp)

        var currentPosition = 0
        var range = NSMakeRange(0, 0)
        var ret: xz_ret = XZ_OK

        // Decoding loop
        while true {
            var signature = [UInt8](count: 6, repeatedValue: 0)
            let magicBit: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]
            range = NSMakeRange(currentPosition, 6)
            file.subdataWithRange(range).getBytes(&signature, length: 6)

            // Check magic number for XZ stream
            while magicBit != signature {
                // Write chunk as uncompressed data if not XZ stream
                range = NSMakeRange(currentPosition, 1 << 24)
                fileHandle?.writeData(file.subdataWithRange(range))

                // Uncompressed chunks are always 16MB
                currentPosition += 1 << 24
                range = NSMakeRange(currentPosition, 6)
                file.subdataWithRange(range).getBytes(&signature, length: 6)
            }

            // Decompresses a single XZ stream
            while currentPosition <= file.length {
                // Check if data from input buffer has already been processed
                if buffer.in_pos == buffer.in_size {
                    // Reset buffer and then move on to the next data frame
                    buffer.in_size = min(file.length - currentPosition, bufferSize)
                    buffer.in_pos = 0
                    range = NSMakeRange(currentPosition, buffer.in_size)

                    file.getBytes(&inBuffer, range: range)
                    currentPosition += buffer.in_size
                }

                // Run the decoder
                ret = xz_dec_run(decoder, &buffer)

                // Flush data to disk once output buffer is full
                if buffer.out_pos == bufferSize {
                    fileHandle?.writeData(NSData(bytes: outBuffer, length: buffer.out_pos))
                    buffer.out_pos = 0
                }

                // If everything is ok, go back to the beginning of the loop
                if ret != XZ_OK {
                    break
                }
            }

            // We reached either the end of the current stream or the
            // end of the file. Either way, we should flush the output
            // buffer to disk before proceeding.

            fileHandle?.writeData(NSData(bytes: outBuffer, length: buffer.out_pos))
            buffer.out_pos = 0

            // Reached end of file
            if currentPosition == file.length {
                // Deallocate XZ decoder object
                xz_dec_end(decoder)

                // Remove input file
                do {
                    try NSFileManager.defaultManager().removeItemAtURL(path)
                }
                catch {
                    exitWithError("File manager error")
                }

                return NSURL(fileURLWithPath: temp)
            }

            if ret != XZ_STREAM_END {
                exitWithError("Decompression error")
            }

            // Payload is composed of multiple, concatenated XZ streams.
            // Set position to the start of the next stream
            currentPosition += buffer.in_pos - buffer.in_size

            // Reset decoder state
            buffer.in_size = 0
            buffer.in_pos = 0
            buffer.out_pos = 0
            xz_dec_reset(decoder)
        }
    }

    return nil
}

func payloadExtract(path: NSURL) -> NSURL? {
    // Based on payload file format specification by Jonathan Levin
    // Website: http://newosxbook.com/articles/OTA.html

    print("Extracting payload")

    if let file = try? NSData(contentsOfURL: path, options: .DataReadingMappedIfSafe) {
        let outputDir = Process.arguments[2]
        let fm = NSFileManager.defaultManager()

        var currentPosition = 0
        var range = NSMakeRange(0, 0)

        var name = ""
        var nameLength = 0
        var fileSize = 0

        while currentPosition < file.length {
            // Release objects after each loop iteration
            autoreleasepool {
                // File size
                currentPosition += 6
                range = NSMakeRange(currentPosition, 4)

                if let i = file.subdataWithRange(range).UInt32Value?.byteSwapped {
                    fileSize = Int(i)
                }

                // File name length
                currentPosition += 16
                range = NSMakeRange(currentPosition, 2)

                if let i = file.subdataWithRange(range).UInt16Value?.byteSwapped {
                    nameLength = Int(i)
                }

                // File name
                currentPosition += 8
                range = NSMakeRange(currentPosition, Int(nameLength))
                let data = file.subdataWithRange(range)

                if let i = String(data: data, encoding: NSUTF8StringEncoding) {
                    name = i
                }

                // Get range of bytes containing file data
                currentPosition += Int(nameLength)
                range = NSMakeRange(currentPosition, fileSize)

                // Check if file is a directory
                if fileSize != 0 {
                    let path = "\(outputDir)/\(name)"

                    // Create any missing directories in directory path
                    createIntermediateDirectoriesForFile(NSURL(fileURLWithPath: path))
                    fm.createFileAtPath(path, contents: nil, attributes: nil)

                    let fileHandle = NSFileHandle(forWritingAtPath: path)
                    fileHandle?.writeData(file.subdataWithRange(range))
                }

                currentPosition += fileSize
            }
        }

        // Remove input file after writing output
        do {
            try NSFileManager.defaultManager().removeItemAtURL(path)
        }
        catch {
            exitWithError("File manager error")
        }

        return NSURL(fileURLWithPath: outputDir)
    }

    return nil
}

// Print usage message if incorrect number of
// arguments are supplied
if Process.argc != 3 {
    printUsage()
}

// Clean up if user terminates early
signal(SIGINT, handleSignal)
signal(SIGQUIT, handleSignal)

let path = NSURL(fileURLWithPath: Process.arguments[1])

if path.pathExtension != "zip" {
    print("Expected zip file as input")
    exit(1)
}

// Specify extraction order. Upon success, remove
// temporary directory and print to console.
if let zip = zipExtract(path), pbzx = pbzxExtract(zip) {
    if let xz = xzExtract(pbzx), payload = payloadExtract(xz) {
        removeTemporaryDirectory()
        print("Done.")
    }
}