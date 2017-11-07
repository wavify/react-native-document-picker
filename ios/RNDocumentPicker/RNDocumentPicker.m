#import "RNDocumentPicker.h"

#if __has_include(<React/RCTConvert.h>)
#import <React/RCTConvert.h>
#import <React/RCTBridge.h>
#else // back compatibility for RN version < 0.40
#import "RCTConvert.h"
#import "RCTBridge.h"
#endif

#define IDIOM    UI_USER_INTERFACE_IDIOM()
#define IPAD     UIUserInterfaceIdiomPad

#import <Photos/Photos.h>
#import <AssetsLibrary/AssetsLibrary.h>
@import MobileCoreServices;

@interface RNDocumentPicker () <UIDocumentMenuDelegate,UIDocumentPickerDelegate,UIImagePickerControllerDelegate>
@end


@implementation RNDocumentPicker {
    NSMutableArray *composeViews;
    NSMutableArray *composeCallbacks;
}

@synthesize bridge = _bridge;

- (instancetype)init
{
    if ((self = [super init])) {
        composeCallbacks = [[NSMutableArray alloc] init];
        composeViews = [[NSMutableArray alloc] init];
    }
    return self;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(show:(NSDictionary *)options
                  callback:(RCTResponseSenderBlock)callback) {
    UIViewController *rootViewController = [[[[UIApplication sharedApplication]delegate] window] rootViewController];
    while (rootViewController.modalViewController) {
      rootViewController = rootViewController.modalViewController;
    }

    NSArray *allowedUTIs = [RCTConvert NSArray:options[@"filetype"]];
    UIDocumentMenuViewController *documentPicker = [[UIDocumentMenuViewController alloc] initWithDocumentTypes:(NSArray *)allowedUTIs inMode:UIDocumentPickerModeImport];

    [composeCallbacks addObject:callback];

    documentPicker.delegate = self;
  [documentPicker addOptionWithTitle:@"Photo Library" image:nil order:UIDocumentMenuOrderFirst handler:^{
      UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
      
      imagePickerController.delegate = self;
      imagePickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
      imagePickerController.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
      [rootViewController presentViewController:imagePickerController animated:YES completion:nil];
    }];
    [documentPicker addOptionWithTitle:@"Take Photo or Video" image:nil order:UIDocumentMenuOrderFirst handler:^{
      UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
      
      imagePickerController.delegate = self;
      imagePickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
      imagePickerController.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
      [rootViewController presentViewController:imagePickerController animated:YES completion:nil];
    }];
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;

    if ( IDIOM == IPAD ) {
        NSNumber *top = [RCTConvert NSNumber:options[@"top"]];
        NSNumber *left = [RCTConvert NSNumber:options[@"left"]];
        [documentPicker.popoverPresentationController setSourceRect: CGRectMake([left floatValue], [top floatValue], 0, 0)];
        [documentPicker.popoverPresentationController setSourceView: rootViewController.view];
    }

    [rootViewController presentViewController:documentPicker animated:YES completion:nil];
}


- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker {
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;

    UIViewController *rootViewController = [[[[UIApplication sharedApplication]delegate] window] rootViewController];
    
    while (rootViewController.modalViewController) {
        rootViewController = rootViewController.modalViewController;
    }
    if ( IDIOM == IPAD ) {
        [documentPicker.popoverPresentationController setSourceRect: CGRectMake(rootViewController.view.frame.size.width/2, rootViewController.view.frame.size.height - rootViewController.view.frame.size.height / 6, 0, 0)];
        [documentPicker.popoverPresentationController setSourceView: rootViewController.view];
    }

    [rootViewController presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTResponseSenderBlock callback = [composeCallbacks lastObject];
        [composeCallbacks removeLastObject];

        [url startAccessingSecurityScopedResource];

        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
        __block NSError *error;

        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingResolvesSymbolicLink error:&error byAccessor:^(NSURL *newURL) {
            NSMutableDictionary* result = [NSMutableDictionary dictionary];

            [result setValue:newURL.absoluteString forKey:@"uri"];
            [result setValue:[newURL lastPathComponent] forKey:@"fileName"];

            NSError *attributesError = nil;
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:newURL.path error:&attributesError];
            if(!attributesError) {
                [result setValue:[fileAttributes objectForKey:NSFileSize] forKey:@"fileSize"];
            } else {
                NSLog(@"%@", attributesError);
            }

            callback(@[[NSNull null], result]);
        }];

        [url stopAccessingSecurityScopedResource];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
  RCTResponseSenderBlock callback = [composeCallbacks lastObject];
  [composeCallbacks removeLastObject];
  
  NSURL *imageURL = [info valueForKey:UIImagePickerControllerReferenceURL];
  NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
  NSString *fileName;
  if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
    NSString *tempFileName = [[NSUUID UUID] UUIDString];
    if (imageURL && [[imageURL absoluteString] rangeOfString:@"ext=GIF"].location != NSNotFound) {
      fileName = [tempFileName stringByAppendingString:@".gif"];
    }
    else if (imageURL && [[imageURL absoluteString] rangeOfString:@"ext=PNG"].location != NSNotFound) {
      fileName = [tempFileName stringByAppendingString:@".png"];
    }
    else {
      fileName = [tempFileName stringByAppendingString:@".jpg"];
    }
  }
  else {
    NSURL *videoURL = info[UIImagePickerControllerMediaURL];
    fileName = videoURL.lastPathComponent;
  }
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
  NSString *uri = [NSString stringWithFormat:@"file://%@", path];
  
  if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
    if (imageURL) {
      PHAsset *pickedAsset = [PHAsset fetchAssetsWithALAssetURLs:@[imageURL] options:nil].lastObject;
      NSString *originalFilename = [self originalFilenameForAsset:pickedAsset assetType:PHAssetResourceTypePhoto];
      fileName = originalFilename ?: [NSNull null];
    } else {
      NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
      [dateFormat setDateFormat:@"YYYY-MM-dd_HH-mm-ss"];
      NSString *extension = [path pathExtension];
      fileName = [NSString stringWithFormat:@"IMG-%@.%@", [dateFormat stringFromDate:[NSDate new]], extension];
    }
    
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
    if (imageURL && [[imageURL absoluteString] rangeOfString:@"ext=GIF"].location != NSNotFound) {
      ALAssetsLibrary* assetsLibrary = [[ALAssetsLibrary alloc] init];
      [assetsLibrary assetForURL:imageURL resultBlock:^(ALAsset *asset) {
        ALAssetRepresentation *rep = [asset defaultRepresentation];
        Byte *buffer = (Byte*)malloc(rep.size);
        NSUInteger buffered = [rep getBytes:buffer fromOffset:0.0 length:rep.size error:nil];
        NSData *data = [NSData dataWithBytesNoCopy:buffer length:buffered freeWhenDone:YES];
        [data writeToFile:path atomically:YES];
        
        NSMutableDictionary *gifResponse = [[NSMutableDictionary alloc] init];
        
        NSString *dataString = [data base64EncodedStringWithOptions:0];
        [gifResponse setObject:dataString forKey:@"data"];
        
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        [gifResponse setObject:[fileURL absoluteString] forKey:@"uri"];
        
        [gifResponse setValue:fileName forKey:@"fileName"];
        
        callback(@[[NSNull null], gifResponse]);
        dispatch_async(dispatch_get_main_queue(), ^{
          [picker dismissViewControllerAnimated:YES completion:nil];
        });
      } failureBlock:^(NSError *error) {
        callback(@[@{@"error": error.localizedFailureReason}, [NSNull null]]);
      }];
      return;
    }
    
    image = [self fixOrientation:image];
    
    NSData *data;
    if (imageURL && [[imageURL absoluteString] rangeOfString:@"ext=PNG"].location != NSNotFound) {
      data = UIImagePNGRepresentation(image);
    }
    else {
      data = UIImageJPEGRepresentation(image, 1.f);
    }
    
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    [data writeToFile:path atomically:YES];
  } else {
    NSURL *videoRefURL = info[UIImagePickerControllerReferenceURL];
    NSURL *videoURL = info[UIImagePickerControllerMediaURL];
    NSURL *videoDestinationURL = [NSURL fileURLWithPath:path];
    
    if (videoRefURL) {
      PHAsset *pickedAsset = [PHAsset fetchAssetsWithALAssetURLs:@[videoRefURL] options:nil].lastObject;
      NSString *originalFilename = [self originalFilenameForAsset:pickedAsset assetType:PHAssetResourceTypeVideo];
      fileName = originalFilename ?: [NSNull null];
    }
    
    if ([videoURL.URLByResolvingSymlinksInPath.path isEqualToString:videoDestinationURL.URLByResolvingSymlinksInPath.path] == NO) {
      NSFileManager *fileManager = [NSFileManager defaultManager];
      
      // Delete file if it already exists
      if ([fileManager fileExistsAtPath:videoDestinationURL.path]) {
        [fileManager removeItemAtURL:videoDestinationURL error:nil];
      }
      
      if (videoURL) { // Protect against reported crash
        NSError *error = nil;
        [fileManager moveItemAtURL:videoURL toURL:videoDestinationURL error:&error];
        if (error) {
          callback(@[@{@"error": error.localizedFailureReason}, [NSNull null]]);
          return;
        }
      }
    }
    
    path = videoDestinationURL.absoluteString;
  }
  
  NSMutableDictionary* result = [NSMutableDictionary dictionary];
  [result setValue:uri forKey:@"uri"];
  [result setValue:fileName forKey:@"fileName"];
  
  callback(@[[NSNull null], result]);
  dispatch_async(dispatch_get_main_queue(), ^{
    [picker dismissViewControllerAnimated:YES completion:nil];
  });
}

- (UIImage *)fixOrientation:(UIImage *)srcImg {
  if (srcImg.imageOrientation == UIImageOrientationUp) {
    return srcImg;
  }
  
  CGAffineTransform transform = CGAffineTransformIdentity;
  switch (srcImg.imageOrientation) {
    case UIImageOrientationDown:
    case UIImageOrientationDownMirrored:
      transform = CGAffineTransformTranslate(transform, srcImg.size.width, srcImg.size.height);
      transform = CGAffineTransformRotate(transform, M_PI);
      break;
      
    case UIImageOrientationLeft:
    case UIImageOrientationLeftMirrored:
      transform = CGAffineTransformTranslate(transform, srcImg.size.width, 0);
      transform = CGAffineTransformRotate(transform, M_PI_2);
      break;
      
    case UIImageOrientationRight:
    case UIImageOrientationRightMirrored:
      transform = CGAffineTransformTranslate(transform, 0, srcImg.size.height);
      transform = CGAffineTransformRotate(transform, -M_PI_2);
      break;
    case UIImageOrientationUp:
    case UIImageOrientationUpMirrored:
      break;
  }
  
  switch (srcImg.imageOrientation) {
    case UIImageOrientationUpMirrored:
    case UIImageOrientationDownMirrored:
      transform = CGAffineTransformTranslate(transform, srcImg.size.width, 0);
      transform = CGAffineTransformScale(transform, -1, 1);
      break;
      
    case UIImageOrientationLeftMirrored:
    case UIImageOrientationRightMirrored:
      transform = CGAffineTransformTranslate(transform, srcImg.size.height, 0);
      transform = CGAffineTransformScale(transform, -1, 1);
      break;
    case UIImageOrientationUp:
    case UIImageOrientationDown:
    case UIImageOrientationLeft:
    case UIImageOrientationRight:
      break;
  }
  
  CGContextRef ctx = CGBitmapContextCreate(NULL, srcImg.size.width, srcImg.size.height, CGImageGetBitsPerComponent(srcImg.CGImage), 0, CGImageGetColorSpace(srcImg.CGImage), CGImageGetBitmapInfo(srcImg.CGImage));
  CGContextConcatCTM(ctx, transform);
  switch (srcImg.imageOrientation) {
    case UIImageOrientationLeft:
    case UIImageOrientationLeftMirrored:
    case UIImageOrientationRight:
    case UIImageOrientationRightMirrored:
      CGContextDrawImage(ctx, CGRectMake(0,0,srcImg.size.height,srcImg.size.width), srcImg.CGImage);
      break;
      
    default:
      CGContextDrawImage(ctx, CGRectMake(0,0,srcImg.size.width,srcImg.size.height), srcImg.CGImage);
      break;
  }
  
  CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
  UIImage *img = [UIImage imageWithCGImage:cgimg];
  CGContextRelease(ctx);
  CGImageRelease(cgimg);
  return img;
}

- (NSString * _Nullable)originalFilenameForAsset:(PHAsset * _Nullable)asset assetType:(PHAssetResourceType)type {
  if (!asset) { return nil; }
  
  PHAssetResource *originalResource;
  // Get the underlying resources for the PHAsset (PhotoKit)
  NSArray<PHAssetResource *> *pickedAssetResources = [PHAssetResource assetResourcesForAsset:asset];
  
  // Find the original resource (underlying image) for the asset, which has the desired filename
  for (PHAssetResource *resource in pickedAssetResources) {
    if (resource.type == type) {
      originalResource = resource;
    }
  }
  
  return originalResource.originalFilename;
}

@end
