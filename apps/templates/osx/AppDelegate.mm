//
//  AppDelegate.m
//
//  Created by abstephens on 1/21/15.
//  Copyright (c) 2015 Google. All rights reserved.
//

#include <algorithm>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "AppDelegate.h"
#import "AppProtocol.h"
#import "HalideRuntime.h"

// This file is generated by the CMake build and contains a list of test
// functions to execute.
#import "test_symbols.h"

@interface AppDelegate ()
@property (retain) NSWindow *window;
@property (retain) WebView *outputView;
@end

@implementation AppDelegate

- (instancetype)init
{
  self = [super init];
  if (self) {
    _window = [[NSWindow alloc] init];
    _outputView = [[WebView alloc] init];
    _database = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {

  // Setup the application protocol handler
  [NSURLProtocol registerClass:[AppProtocol class]];

  // Setup a very basic main menu
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  [[NSApplication sharedApplication] setMainMenu:menu];

  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@""
                                                action:nil
                                         keyEquivalent:@""];

  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

  [item setSubmenu:fileMenu];
  [menu addItem:item];

  [fileMenu addItemWithTitle:@"Quit"
                      action:@selector(terminate:)
               keyEquivalent:@"q"];

  // Setup the application window
  [self.window setFrame:CGRectMake(0, 0, 768, 1024) display:NO];
  [self.window setContentView:self.outputView];
  [self.window setStyleMask:self.window.styleMask |
    NSResizableWindowMask |
    NSClosableWindowMask |
    NSMiniaturizableWindowMask |
    NSTitledWindowMask ];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {

  // Setup the main menu
  [self.window makeKeyAndOrderFront:self];

  // Setup the page load delegate
  self.outputView.frameLoadDelegate = self;

  // Load the test document
  NSURL* url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
  [self.outputView.mainFrame loadRequest:[NSURLRequest requestWithURL:url]];
}

// This method is called after the main webpage is loaded. It calls the test
// function that will eventually output to the page via the echo method below.
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
  self.database = [NSMutableDictionary dictionary];

  // Call the test functions
  int num_test_symbols = sizeof(test_symbols) / sizeof(test_symbols[0]);
  if (num_test_symbols == 0) {
    [self echo:[NSString stringWithFormat:@"<div class='error'>No test symbols defined.</div>"]];
    return;
  }

  for (int i = 0; i != num_test_symbols; ++i) {

    // Attempt to load the symbol
    test_function_t func = (test_function_t)test_symbols[i];
    if (!func) {
      [self echo:[NSString stringWithFormat:@"<div class='error'>%s not found</div>",test_names[i]]];
      continue;
    }

    // Execute the function
    int result = func();

    [self echo:[NSString stringWithFormat:@"%s returned %d",test_names[i],result]];
  }
}

// This message appends the specified string, which may contain HTML tags to the
// document displayed in the webview.
- (void)echo:(NSString*)message {
  NSString* htmlMessage = [message stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];

  htmlMessage = [NSString stringWithFormat:@"echo(\"%@\");",htmlMessage];

  [self.outputView stringByEvaluatingJavaScriptFromString:htmlMessage];
}

@end

extern "C"
void halide_print(void *user_context, const char * message)
{
  AppDelegate* app = [NSApp delegate];
  [app echo:[NSString stringWithCString:message encoding:NSUTF8StringEncoding]];

  NSLog(@"%s",message);
}

extern "C"
void halide_error(void *user_context, const char * message)
{
  AppDelegate* app = [NSApp delegate];
  [app echo:[NSString stringWithFormat:@"<div class='error'>%s</div>",message]];

  NSLog(@"%s",message);
}

extern "C"
int halide_buffer_display(const buffer_t* buffer)
{
  // Convert the buffer_t to an NSImage

  // TODO: This code should handle channel types larger than one byte.
  void* data_ptr = buffer->host;

  size_t width            = buffer->extent[0];
  size_t height           = buffer->extent[1];
  size_t channels         = buffer->extent[2];
  size_t bitsPerComponent = buffer->elem_size*8;

  // For planar data, there is one channel across the row
  size_t src_bytesPerRow      = width*buffer->elem_size;
  size_t dst_bytesPerRow      = width*channels*buffer->elem_size;

  size_t totalBytes = width*height*channels*buffer->elem_size;

  // Unlike Mac OS X Cocoa which directly supports planar data via
  // NSBitmapImageRep, in iOS we must create a CGImage from the pixel data and
  // Quartz only supports interleaved formats.
  unsigned char* src_buffer = (unsigned char*)data_ptr;
  unsigned char* dst_buffer = (unsigned char*)malloc(totalBytes);

  // Interleave the data
  for (size_t c=0;c!=buffer->extent[2];++c) {
    for (size_t y=0;y!=buffer->extent[1];++y) {
      for (size_t x=0;x!=buffer->extent[0];++x) {
        size_t src = x + y*src_bytesPerRow + c * (height*src_bytesPerRow);
        size_t dst = c + x*channels + y*dst_bytesPerRow;
        dst_buffer[dst] = src_buffer[src];
      }
    }
  }

  CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, dst_buffer, totalBytes, NULL);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

  CGImageRef cgImage = CGImageCreate(width,
                                     height,
                                     bitsPerComponent,
                                     bitsPerComponent*channels,
                                     dst_bytesPerRow,
                                     colorSpace,
                                     kCGBitmapByteOrderDefault,
                                     provider,
                                     NULL,
                                     NO,
                                     kCGRenderingIntentDefault);

  NSImage* image = [[NSImage alloc] initWithCGImage:cgImage size:NSZeroSize];

  // Cleanup
  CGImageRelease(cgImage);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);

  // Convert the NSImage to a png
  NSData* tiffData = [image TIFFRepresentation];
  NSBitmapImageRep* rep = [NSBitmapImageRep imageRepsWithData:tiffData][0];
  NSData* data = [rep representationUsingType:NSPNGFileType properties:nil];

  // Construct a name for the image resource
  static int counter = 0;
  NSString* url = [NSString stringWithFormat:@"%@:///buffer_t%d",kAppProtocolURLScheme,counter++];

  // Add the buffer to the result database
  AppDelegate* app = [NSApp delegate];
  app.database[url] = data;

  // Load the image through a URL
  [app echo:[NSString stringWithFormat:@"<img class='output' src='%@'></img>",url]];

  return 0;
}

extern "C"
int halide_buffer_print(const buffer_t* buffer)
{
  NSMutableArray* output = [NSMutableArray array];

  [output addObject:[NSString stringWithFormat:@"elem_size = %d<br>",buffer->elem_size]];
  [output addObject:[NSString stringWithFormat:@"extent = [ %d %d %d %d ]<br>",
      buffer->extent[0],buffer->extent[1],buffer->extent[2],buffer->extent[3]]];
  [output addObject:[NSString stringWithFormat:@"stride = [ %d %d %d %d ]<br>",
      buffer->stride[0],buffer->stride[1],buffer->stride[2],buffer->stride[3]]];
  [output addObject:[NSString stringWithFormat:@"min = [ %d %d %d %d ]<br>",
      buffer->min[0],buffer->min[1],buffer->min[2],buffer->min[3]]];
  [output addObject:@"host = [<br>"];
  for (int i3 = 0; i3 < std::max(1, buffer->extent[3]); ++i3) {
      [output addObject:[NSString stringWithFormat:@"---- Z=%d ---- <br>", i3]];
      for (int i1 = 0; i1 < std::max(1, buffer->extent[1]); ++i1) {
          for (int i0 = 0; i0 < std::max(1, buffer->extent[0]); ++i0) {
              for (int i2 = 0; i2 < std::max(1, buffer->extent[2]); ++i2) {
                  int offset = i0*buffer->stride[0] + i1*buffer->stride[1] + i2*buffer->stride[2] + i3*buffer->stride[3];
                  switch (buffer->elem_size) {
                      case 1: [output addObject:[NSString stringWithFormat:@" %02x",((uint8_t*)buffer->host)[offset]]]; break;
                      case 2: [output addObject:[NSString stringWithFormat:@" %02x",((uint16_t*)buffer->host)[offset]]]; break;
                      // TODO: add a way to distinguish between int32 and float.
                      case 4: [output addObject:[NSString stringWithFormat:@" %f",((float*)buffer->host)[offset]]]; break;
                  }
              }
              [output addObject:@","];
          }
          [output addObject:@"<br>"];
      }
  }
  [output addObject:@"<br>]<br>"];

  NSString* text = [output componentsJoinedByString:@""];

  // Output the buffer as a string
  AppDelegate* app = [NSApp delegate];
  [app echo:[NSString stringWithFormat:@"<pre class='data'>%@</pre><br>",text]];

  return 0;
}

