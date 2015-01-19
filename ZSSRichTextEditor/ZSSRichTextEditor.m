//
//  ZSSRichTextEditorViewController.m
//  ZSSRichTextEditor
//
//  Created by Nicholas Hubbard on 11/30/13.
//  Copyright (c) 2013 Zed Said Studio. All rights reserved.
//

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "ZSSRichTextEditor.h"
#import "ZSSBarButtonItem.h"
#import "HRColorUtil.h"
#import "ZSSTextView.h"


@interface UIWebView (HackishAccessoryHiding)
@property (nonatomic, assign) BOOL hidesInputAccessoryView;
@end

@implementation UIWebView (HackishAccessoryHiding)

static const char * const hackishFixClassName = "UIWebBrowserViewMinusAccessoryView";
static Class hackishFixClass = Nil;

- (UIView *)hackishlyFoundBrowserView {
    UIScrollView *scrollView = self.scrollView;
    
    UIView *browserView = nil;
    for (UIView *subview in scrollView.subviews) {
        if ([NSStringFromClass([subview class]) hasPrefix:@"UIWebBrowserView"]) {
            browserView = subview;
            break;
        }
    }
    return browserView;
}

- (id)methodReturningNil {
    return nil;
}

- (void)ensureHackishSubclassExistsOfBrowserViewClass:(Class)browserViewClass {
    if (!hackishFixClass) {
        Class newClass = objc_allocateClassPair(browserViewClass, hackishFixClassName, 0);
        newClass = objc_allocateClassPair(browserViewClass, hackishFixClassName, 0);
        IMP nilImp = [self methodForSelector:@selector(methodReturningNil)];
        class_addMethod(newClass, @selector(inputAccessoryView), nilImp, "@@:");
        objc_registerClassPair(newClass);
        
        hackishFixClass = newClass;
    }
}

- (BOOL) hidesInputAccessoryView {
    UIView *browserView = [self hackishlyFoundBrowserView];
    return [browserView class] == hackishFixClass;
}

- (void) setHidesInputAccessoryView:(BOOL)value {
    UIView *browserView = [self hackishlyFoundBrowserView];
    if (browserView == nil) {
        return;
    }
    [self ensureHackishSubclassExistsOfBrowserViewClass:[browserView class]];
	
    if (value) {
        object_setClass(browserView, hackishFixClass);
    }
    else {
        Class normalClass = objc_getClass("UIWebBrowserView");
        object_setClass(browserView, normalClass);
    }
    [browserView reloadInputViews];
}

@end

@interface ZSSRichTextEditor ()
@property (nonatomic, strong) UIScrollView *toolBarScroll;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) UIView *toolbarHolder;
@property (nonatomic, strong) NSString *htmlString;
@property (nonatomic, strong) UIWebView *editorView;
@property (nonatomic, strong) ZSSTextView *sourceView;
@property (nonatomic) CGRect editorViewFrame;
@property (nonatomic) BOOL resourcesLoaded;
@property (nonatomic, strong) NSArray *editorItemsEnabled;
@property (nonatomic, strong) UIAlertView *alertView;
@property (nonatomic, strong) NSString *selectedLinkURL;
@property (nonatomic, strong) NSString *selectedLinkTitle;
@property (nonatomic, strong) NSString *selectedImageURL;
@property (nonatomic, strong) NSString *selectedImageAlt;
@property (nonatomic, strong) UIBarButtonItem *keyboardItem;
@property (nonatomic, strong) NSMutableArray *customBarButtonItems;
@property (nonatomic, strong) NSMutableArray *customZSSBarButtonItems;
@property (nonatomic, strong) NSString *internalHTML;
@property (nonatomic) BOOL editorLoaded;
- (NSString *)removeQuotesFromHTML:(NSString *)html;
- (NSString *)tidyHTML:(NSString *)html;
- (void)enableToolbarItems:(BOOL)enable;
- (BOOL)isIpad;
@end

@implementation ZSSRichTextEditor

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //custom from cloud
//    if([[[UIDevice currentDevice] systemVersion] floatValue] >= 5.0) {
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
//    }
    
    self.editorLoaded = NO;
    self.shouldShowKeyboard = NO;
    self.formatHTML = YES;
    
    // Source View
    CGRect frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    self.sourceView = [[ZSSTextView alloc] initWithFrame:frame];
    NSLog(@"width : %f , Height : %f", self.view.frame.size.width, self.view.frame.size.height );
    self.sourceView.hidden = YES;
    self.sourceView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.sourceView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.sourceView.font = [UIFont fontWithName:@"Courier" size:13.0];
    self.sourceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.sourceView.autoresizesSubviews = YES;
    self.sourceView.delegate = self;
    [self.view addSubview:self.sourceView];
    
    // Editor View
    self.editorView = [[UIWebView alloc] initWithFrame:frame];
    self.editorView.delegate = self;
    self.editorView.hidesInputAccessoryView = YES;
    self.editorView.keyboardDisplayRequiresUserAction = NO;
    self.editorView.scalesPageToFit = YES;
    self.editorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.editorView.dataDetectorTypes = UIDataDetectorTypeNone;
    self.editorView.scrollView.bounces = NO;
    self.editorView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.editorView];
    
    // Scrolling View
    self.toolBarScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, [self isIpad] ? self.view.frame.size.width : self.view.frame.size.width - 44, 44)];
    self.toolBarScroll.backgroundColor = [UIColor clearColor];
    self.toolBarScroll.showsHorizontalScrollIndicator = NO;
    
    // Toolbar with icons
    self.toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
    self.toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.toolbar.backgroundColor = [UIColor clearColor];
    [self.toolBarScroll addSubview:self.toolbar];
    self.toolBarScroll.autoresizingMask = self.toolbar.autoresizingMask;
    
    // Background Toolbar
    UIToolbar *backgroundToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    backgroundToolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // Parent holding view
    self.toolbarHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 244, self.view.frame.size.width, 44)];//self.view.frame.size.height, self.view.frame.size.width, 44)];
    self.toolbarHolder.autoresizingMask = self.toolbar.autoresizingMask;
    [self.toolbarHolder setAlpha:0];
    [self.toolbarHolder addSubview:self.toolBarScroll];
    [self.toolbarHolder insertSubview:backgroundToolbar atIndex:0];
    
    // Hide Keyboard
    if (![self isIpad]) {
        
        // Toolbar holder used to crop and position toolbar
        UIView *toolbarCropper = [[UIView alloc] initWithFrame:CGRectMake(self.view.frame.size.width-44, 0, 44, 44)];
        toolbarCropper.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        toolbarCropper.clipsToBounds = YES;
        
        // Use a toolbar so that we can tint
        UIToolbar *keyboardToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(-7, -1, 44, 44)];
        [toolbarCropper addSubview:keyboardToolbar];
        
        self.keyboardItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSkeyboard.png"] style:UIBarButtonItemStylePlain target:self action:@selector(dismissKeyboard)];
        keyboardToolbar.items = @[self.keyboardItem];
        [self.toolbarHolder addSubview:toolbarCropper];
        
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0.6f, 44)];
        line.backgroundColor = [UIColor lightGrayColor];
        line.alpha = 0.7f;
        [toolbarCropper addSubview:line];
    }
    [self.view addSubview:self.toolbarHolder];
    
    // Build the toolbar
    [self buildToolbar];
    
    if (!self.resourcesLoaded) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"editor" ofType:@"html"];
        NSData *htmlData = [NSData dataWithContentsOfFile:filePath];
        NSString *htmlString = [[NSString alloc] initWithData:htmlData encoding:NSUTF8StringEncoding];
        /*在裡引入了 ZSSRickTextEditor.js*/
        NSString *source = [[NSBundle mainBundle] pathForResource:@"ZSSRichTextEditor" ofType:@"js"];
        NSString *jsString = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:source] encoding:NSUTF8StringEncoding];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"<!--editor-->" withString:jsString];
        
        [self.editorView loadHTMLString:htmlString baseURL:self.baseURL];
        self.resourcesLoaded = YES;
    }

}


- (void)setEnabledToolbarItems:(ZSSRichTextEditorToolbar)enabledToolbarItems {
    
    _enabledToolbarItems = enabledToolbarItems;
    [self buildToolbar];
    
}


- (void)setToolbarItemTintColor:(UIColor *)toolbarItemTintColor {
    
    _toolbarItemTintColor = toolbarItemTintColor;
    
    // Update the color
    for (ZSSBarButtonItem *item in self.toolbar.items) {
        item.tintColor = [self barButtonItemDefaultColor];
    }
    self.keyboardItem.tintColor = toolbarItemTintColor;
    
}


- (void)setToolbarItemSelectedTintColor:(UIColor *)toolbarItemSelectedTintColor {
    
    _toolbarItemSelectedTintColor = toolbarItemSelectedTintColor;
    
}


- (void)setPlaceholderText {
    
    NSString *js = [NSString stringWithFormat:@"zss_editor.setPlaceholder(\"%@\");", self.placeholder];
    [self.editorView stringByEvaluatingJavaScriptFromString:js];
    
}

- (void)setFooterHeight:(float)footerHeight {

    NSString *js = [NSString stringWithFormat:@"zss_editor.setFooterHeight(\"%f\");", footerHeight];
    [self.editorView stringByEvaluatingJavaScriptFromString:js];
}

- (void)setContentHeight:(float)contentHeight {
    
    NSString *js = [NSString stringWithFormat:@"zss_editor.contentHeight = %f;", contentHeight];
    [self.editorView stringByEvaluatingJavaScriptFromString:js];
}


- (NSArray *)itemsForToolbar {
    
    NSMutableArray *items = [[NSMutableArray alloc] init];
    
    // None
    if(_enabledToolbarItems & ZSSRichTextEditorToolbarNone)
    {
        return items;
    }
    
    // Bold
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarBold || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *bold = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSbold.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setBold)];
        bold.label = @"bold";
        [items addObject:bold];
        
    }
    
    // Italic
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarItalic || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *italic = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSitalic.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setItalic)];
        italic.label = @"italic";
        [items addObject:italic];
    }
    
    // Underline
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarUnderline || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *underline = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSunderline.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setUnderline)];
        underline.label = @"underline";
        [items addObject:underline];
    }
    
    // Image
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarInsertImage || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *insertImage = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSimage.png"] style:UIBarButtonItemStylePlain target:self action:@selector(insertImage)];
        insertImage.label = @"image";
        [items addObject:insertImage];
    }
    
    /*cloud custom here */
    
    //increase font size
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarViewSource || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *increacesFortSize = [[ZSSBarButtonItem alloc] initWithTitle:@" + " style:UIBarButtonItemStylePlain target:self action:@selector(increaseFontSize)];
        increacesFortSize.label = @"increacesFontSize";
        [items addObject:increacesFortSize];
        
    }
    
    //decrease fone size
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarViewSource || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *decreacesFortSize = [[ZSSBarButtonItem alloc] initWithTitle:@" - " style:UIBarButtonItemStylePlain target:self action:@selector(decreaseFontSize)];
        decreacesFortSize.label = @"decreacesFontSize";
        [items addObject:decreacesFortSize];
        
    }
    
    // Insert Link
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarInsertLink || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *insertLink = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSlink.png"] style:UIBarButtonItemStylePlain target:self action:@selector(insertLink)];
        insertLink.label = @"link";
        [items addObject:insertLink];
    }
    
    // Remove Link
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarRemoveLink || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *removeLink = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSunlink.png"] style:UIBarButtonItemStylePlain target:self action:@selector(removeLink)];
        removeLink.label = @"removeLink";
        [items addObject:removeLink];
    }
    
    // Quick Link
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarQuickLink || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *quickLink = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSquicklink.png"] style:UIBarButtonItemStylePlain target:self action:@selector(quickLink)];
        quickLink.label = @"quickLink";
        [items addObject:quickLink];
    }
    
    // Unordered List
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarUnorderedList || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *ul = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSunorderedlist.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setUnorderedList)];
        ul.label = @"unorderedList";
        [items addObject:ul];
    }
    
    // Ordered List
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarOrderedList || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *ol = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSorderedlist.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setOrderedList)];
        ol.label = @"orderedList";
        [items addObject:ol];
    }
    
    /*dolphin update here*/
    // Load more
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarViewSource || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        /*圖片大小跟原本的不合，先不處理‌‌*/
        //        ZSSBarButtonItem *loadMore = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"more.png"] style:UIBarButtonItemStylePlain target:self action:@selector(loadMore:)];
        ZSSBarButtonItem *loadMore = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"btn_readmore_h.png"] style:UIBarButtonItemStylePlain target:self action:@selector(loadMore:)];
        //        ZSSBarButtonItem *loadMore = [[ZSSBarButtonItem alloc] initWithTitle:@"more" style:UIBarButtonItemStylePlain target:self action:@selector(loadMore:)];
        loadMore.label = @"loadMore";
        [items addObject:loadMore];
    }
    
    // Show Source
    if (_enabledToolbarItems & ZSSRichTextEditorToolbarViewSource || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
        ZSSBarButtonItem *showSource = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSviewsource.png"] style:UIBarButtonItemStylePlain target:self action:@selector(showHTMLSource:)];
        showSource.label = @"source";
        [items addObject:showSource];
    }
    
    return [NSArray arrayWithArray:items];
    
//    // Subscript
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarSubscript || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *subscript = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSsubscript.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setSubscript)];
//        subscript.label = @"subscript";
//        [items addObject:subscript];
//    }
//    
//    // Superscript
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarSuperscript || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *superscript = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSsuperscript.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setSuperscript)];
//        superscript.label = @"superscript";
//        [items addObject:superscript];
//    }
//    
//    // Strike Through
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarStrikeThrough || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *strikeThrough = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSstrikethrough.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setStrikethrough)];
//        strikeThrough.label = @"strikeThrough";
//        [items addObject:strikeThrough];
//    }
    

    
//    // Remove Format
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarRemoveFormat || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *removeFormat = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSclearstyle.png"] style:UIBarButtonItemStylePlain target:self action:@selector(removeFormat)];
//        removeFormat.label = @"removeFormat";
//        [items addObject:removeFormat];
//    }
//    
//    // Undo
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarUndo || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *undoButton = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSundo.png"] style:UIBarButtonItemStylePlain target:self action:@selector(undo:)];
//        undoButton.label = @"undo";
//        [items addObject:undoButton];
//    }
//    
//    // Redo
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarRedo || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *redoButton = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSredo.png"] style:UIBarButtonItemStylePlain target:self action:@selector(redo:)];
//        redoButton.label = @"redo";
//        [items addObject:redoButton];
//    }
//    
//    // Align Left
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarJustifyLeft || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *alignLeft = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSleftjustify.png"] style:UIBarButtonItemStylePlain target:self action:@selector(alignLeft)];
//        alignLeft.label = @"justifyLeft";
//        [items addObject:alignLeft];
//    }
//    
//    // Align Center
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarJustifyCenter || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *alignCenter = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSScenterjustify.png"] style:UIBarButtonItemStylePlain target:self action:@selector(alignCenter)];
//        alignCenter.label = @"justifyCenter";
//        [items addObject:alignCenter];
//    }
//    
//    // Align Right
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarJustifyRight || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *alignRight = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSrightjustify.png"] style:UIBarButtonItemStylePlain target:self action:@selector(alignRight)];
//        alignRight.label = @"justifyRight";
//        [items addObject:alignRight];
//    }
//    
//    // Align Justify
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarJustifyFull || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *alignFull = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSforcejustify.png"] style:UIBarButtonItemStylePlain target:self action:@selector(alignFull)];
//        alignFull.label = @"justifyFull";
//        [items addObject:alignFull];
//    }
//    
//    // Paragraph
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarParagraph || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *paragraph = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSparagraph.png"] style:UIBarButtonItemStylePlain target:self action:@selector(paragraph)];
//        paragraph.label = @"p";
//        [items addObject:paragraph];
//    }
//    
//    // Header 1
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarH1 || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *h1 = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSh1.png"] style:UIBarButtonItemStylePlain target:self action:@selector(heading1)];
//        h1.label = @"h1";
//        [items addObject:h1];
//    }
//    
//    // Header 2
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarH2 || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *h2 = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSh2.png"] style:UIBarButtonItemStylePlain target:self action:@selector(heading2)];
//        h2.label = @"h2";
//        [items addObject:h2];
//    }
//    
//    // Header 3
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarH3 || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *h3 = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSh3.png"] style:UIBarButtonItemStylePlain target:self action:@selector(heading3)];
//        h3.label = @"h3";
//        [items addObject:h3];
//    }
//    
//    // Heading 4
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarH4 || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *h4 = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSh4.png"] style:UIBarButtonItemStylePlain target:self action:@selector(heading4)];
//        h4.label = @"h4";
//        [items addObject:h4];
//    }
//    
//    // Header 5
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarH5 || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *h5 = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSh5.png"] style:UIBarButtonItemStylePlain target:self action:@selector(heading5)];
//        h5.label = @"h5";
//        [items addObject:h5];
//    }
//    
//    // Heading 6
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarH6 || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *h6 = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSh6.png"] style:UIBarButtonItemStylePlain target:self action:@selector(heading6)];
//        h6.label = @"h6";
//        [items addObject:h6];
//    }
//    
//    // Text Color
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarTextColor || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *textColor = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSStextcolor.png"] style:UIBarButtonItemStylePlain target:self action:@selector(textColor)];
//        textColor.label = @"textColor";
//        [items addObject:textColor];
//    }
//    
//    // Background Color
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarBackgroundColor || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *bgColor = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSbgcolor.png"] style:UIBarButtonItemStylePlain target:self action:@selector(bgColor)];
//        bgColor.label = @"backgroundColor";
//        [items addObject:bgColor];
//    }
//    
//
//    
//    // Horizontal Rule
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarHorizontalRule || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *hr = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSShorizontalrule.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setHR)];
//        hr.label = @"horizontalRule";
//        [items addObject:hr];
//    }
//    
//    // Indent
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarIndent || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *indent = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSindent.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setIndent)];
//        indent.label = @"indent";
//        [items addObject:indent];
//    }
//    
//    // Outdent
//    if (_enabledToolbarItems & ZSSRichTextEditorToolbarOutdent || _enabledToolbarItems & ZSSRichTextEditorToolbarAll) {
//        ZSSBarButtonItem *outdent = [[ZSSBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ZSSoutdent.png"] style:UIBarButtonItemStylePlain target:self action:@selector(setOutdent)];
//        outdent.label = @"outdent";
//        [items addObject:outdent];
//    }
//    

}

- (void)buildToolbar {

    // Check to see if we have any toolbar items, if not, add them all
    NSArray *items = [self itemsForToolbar];
    if (items.count == 0 && !(_enabledToolbarItems & ZSSRichTextEditorToolbarNone)) {
        _enabledToolbarItems = ZSSRichTextEditorToolbarAll;
        items = [self itemsForToolbar];
    }

    if (self.customZSSBarButtonItems != nil) {
        items = [items arrayByAddingObjectsFromArray:self.customZSSBarButtonItems];
    }

    // get the width before we add custom buttons
    CGFloat toolbarWidth = items.count == 0 ? 0.0f : (CGFloat)(items.count * 39) - 10;

    if(self.customBarButtonItems != nil)
    {
        items = [items arrayByAddingObjectsFromArray:self.customBarButtonItems];
        for(ZSSBarButtonItem *buttonItem in self.customBarButtonItems)
        {
            toolbarWidth += buttonItem.customView.frame.size.width + 11.0f;
        }
    }

    self.toolbar.items = items;
    for (ZSSBarButtonItem *item in items) {
        item.tintColor = [self barButtonItemDefaultColor];
    }

    self.toolbar.frame = CGRectMake(0, 0, toolbarWidth, 44);
    self.toolBarScroll.contentSize = CGSizeMake(self.toolbar.frame.size.width, 44);
}
/*
 因為在PixPanel端是使用 UIViewControllerChildCon
 
 */

- (void)viewDidAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShowOrHide:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShowOrHide:) name:UIKeyboardWillHideNotification object:nil];
    //Custom from Cloud
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
}


- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Editor Interaction

- (void)focusTextEditor {
    self.editorView.keyboardDisplayRequiresUserAction = NO;
    NSString *js = [NSString stringWithFormat:@"zss_editor.focusEditor();"];
    [self.editorView stringByEvaluatingJavaScriptFromString:js];
}

- (void)blurTextEditor {
    NSString *js = [NSString stringWithFormat:@"zss_editor.blurEditor();"];
    [self.editorView stringByEvaluatingJavaScriptFromString:js];
}

- (void)setHTML:(NSString *)html {

    self.internalHTML = html;

    if (self.editorLoaded) {
        [self updateHTML];
    }

}

- (void)updateHTML {

    NSString *html = self.internalHTML;
    self.sourceView.text = html;
    NSString *cleanedHTML = [self removeQuotesFromHTML:self.sourceView.text];
	NSString *trigger = [NSString stringWithFormat:@"zss_editor.setHTML(\"%@\");", cleanedHTML];
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];

}

- (NSString *)getHTML {
    NSString *html = [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.getHTML();"];
    html = [self removeQuotesFromHTML:html];
    html = [self tidyHTML:html];
	return html;
}

- (void)insertHTML:(NSString *)html {
    NSString *cleanedHTML = [self removeQuotesFromHTML:html];
	NSString *trigger = [NSString stringWithFormat:@"zss_editor.insertHTML(\"%@\");", cleanedHTML];
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}


- (NSString *)getText {
    return [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.getText();"];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)showHTMLSource:(ZSSBarButtonItem *)barButtonItem {
    if (self.sourceView.hidden) {
        self.sourceView.text = [self getHTML];
        self.sourceView.hidden = NO;
        barButtonItem.tintColor = [UIColor blackColor];
        self.editorView.hidden = YES;
        [self enableToolbarItems:NO];
    } else {
        [self setHTML:self.sourceView.text];
        barButtonItem.tintColor = [self barButtonItemDefaultColor];
        self.sourceView.hidden = YES;
        self.editorView.hidden = NO;
        [self enableToolbarItems:YES];
    }
}
#warning Fix here
- (void)loadMore:(id)sender {
    NSLog(@"load more button did pressed");
//    NSString *path = [[NSBundle mainBundle] pathForResource:@"more" ofType:@"png"];
    /*因為最後還是要用 html 的方式插圖進去，所以不能用 local 端的圖，要插入一段連結才行*/
    /*dolphin*/
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
    [self insertImage:@"https://s.pixfs.net/app/more.png" alt:@"zss_editor_more"];
    /*
    NSString *trigger = @"zss_editor.insertMore();";
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
    */
}

- (void)increaseFontSize{
    NSString *trigger = @"zss_editor.increaseFontSize()";
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)decreaseFontSize{
    NSString *trigger = @"zss_editor.decreaseFontSize()";
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)removeFormat {
    NSString *trigger = @"zss_editor.removeFormating();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)alignLeft {
    NSString *trigger = @"zss_editor.setJustifyLeft();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)alignCenter {
    NSString *trigger = @"zss_editor.setJustifyCenter();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)alignRight {
    NSString *trigger = @"zss_editor.setJustifyRight();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)alignFull {
    NSString *trigger = @"zss_editor.setJustifyFull();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setBold {
    NSString *trigger = @"zss_editor.setBold();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setItalic {
    NSString *trigger = @"zss_editor.setItalic();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setSubscript {
    NSString *trigger = @"zss_editor.setSubscript();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setUnderline {
    NSString *trigger = @"zss_editor.setUnderline();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setSuperscript {
    NSString *trigger = @"zss_editor.setSuperscript();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setStrikethrough {
    NSString *trigger = @"zss_editor.setStrikeThrough();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setUnorderedList {
    NSString *trigger = @"zss_editor.setUnorderedList();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setOrderedList {
    NSString *trigger = @"zss_editor.setOrderedList();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setHR {
    NSString *trigger = @"zss_editor.setHorizontalRule();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setIndent {
    NSString *trigger = @"zss_editor.setIndent();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)setOutdent {
    NSString *trigger = @"zss_editor.setOutdent();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)heading1 {
    NSString *trigger = @"zss_editor.setHeading('h1');";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)heading2 {
    NSString *trigger = @"zss_editor.setHeading('h2');";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)heading3 {
    NSString *trigger = @"zss_editor.setHeading('h3');";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)heading4 {
    NSString *trigger = @"zss_editor.setHeading('h4');";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)heading5 {
    NSString *trigger = @"zss_editor.setHeading('h5');";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)heading6 {
    NSString *trigger = @"zss_editor.setHeading('h6');";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)paragraph {
    NSString *trigger = @"zss_editor.setParagraph();";
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}

- (void)textColor {
    
    // Save the selection location
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
    
    // Call the picker
    HRColorPickerViewController *colorPicker = [HRColorPickerViewController cancelableFullColorPickerViewControllerWithColor:[UIColor whiteColor]];
    colorPicker.delegate = self;
    colorPicker.tag = 1;
    colorPicker.title = NSLocalizedString(@"Text Color", nil);
    [self.navigationController pushViewController:colorPicker animated:YES];
    
}

- (void)bgColor {
    
    // Save the selection location
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
    
    // Call the picker
    HRColorPickerViewController *colorPicker = [HRColorPickerViewController cancelableFullColorPickerViewControllerWithColor:[UIColor whiteColor]];
    colorPicker.delegate = self;
    colorPicker.tag = 2;
    colorPicker.title = NSLocalizedString(@"BG Color", nil);
    [self.navigationController pushViewController:colorPicker animated:YES];
    
}

- (void)setSelectedColor:(UIColor*)color tag:(int)tag {
   
    NSString *hex = [NSString stringWithFormat:@"#%06x",HexColorFromUIColor(color)];
    NSString *trigger;
    if (tag == 1) {
        trigger = [NSString stringWithFormat:@"zss_editor.setTextColor(\"%@\");", hex];
    } else if (tag == 2) {
        trigger = [NSString stringWithFormat:@"zss_editor.setBackgroundColor(\"%@\");", hex];
    }
	[self.editorView stringByEvaluatingJavaScriptFromString:trigger];
    
}

- (void)undo:(ZSSBarButtonItem *)barButtonItem {
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.undo();"];
}

- (void)redo:(ZSSBarButtonItem *)barButtonItem {
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.redo();"];
}

- (void)insertLink {
    
    // Save the selection location
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
    
    // Show the dialog for inserting or editing a link
    [self showInsertLinkDialogWithLink:self.selectedLinkURL title:self.selectedLinkTitle];
    
}


- (void)showInsertLinkDialogWithLink:(NSString *)url title:(NSString *)title {
    
    // Insert Button Title
    NSString *insertButtonTitle = !self.selectedLinkURL ? NSLocalizedString(@"Insert", nil) : NSLocalizedString(@"Update", nil);
    
    self.alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Insert Link", nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) otherButtonTitles:insertButtonTitle, nil];
    self.alertView.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
    self.alertView.tag = 2;
    UITextField *linkURL = [self.alertView textFieldAtIndex:0];
    linkURL.placeholder = NSLocalizedString(@"URL (required)", nil);
    if (url) {
        linkURL.text = url;
    }
    
    // Picker Button
    UIButton *am = [UIButton buttonWithType:UIButtonTypeCustom];
    am.frame = CGRectMake(0, 0, 25, 25);
    [am setImage:[UIImage imageNamed:@"ZSSpicker.png"] forState:UIControlStateNormal];
    [am addTarget:self action:@selector(showInsertURLAlternatePicker) forControlEvents:UIControlEventTouchUpInside];
    linkURL.rightView = am;
    linkURL.rightViewMode = UITextFieldViewModeAlways;
    
    UITextField *alt = [self.alertView textFieldAtIndex:1];
    alt.secureTextEntry = NO;
    alt.placeholder = NSLocalizedString(@"Title", nil);
    if (title) {
        alt.text = title;
    }
    
    [self.alertView show];
    
}


- (void)insertLink:(NSString *)url title:(NSString *)title {
    
    NSString *trigger = [NSString stringWithFormat:@"zss_editor.insertLink(\"%@\", \"%@\");", url, title];
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
    
}


- (void)updateLink:(NSString *)url title:(NSString *)title {
    NSString *trigger = [NSString stringWithFormat:@"zss_editor.updateLink(\"%@\", \"%@\");", url, title];
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}


- (void)dismissAlertView {
    [self.alertView dismissWithClickedButtonIndex:self.alertView.cancelButtonIndex animated:YES];
}

- (void)addCustomToolbarItemWithButton:(UIButton *)button
{
    if(self.customBarButtonItems == nil)
    {
        self.customBarButtonItems = [NSMutableArray array];
    }
    
    button.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-UltraLight" size:28.5f];
    [button setTitleColor:[self barButtonItemDefaultColor] forState:UIControlStateNormal];
    [button setTitleColor:[self barButtonItemSelectedDefaultColor] forState:UIControlStateHighlighted];
    
    ZSSBarButtonItem *barButtonItem = [[ZSSBarButtonItem alloc] initWithCustomView:button];
    
    [self.customBarButtonItems addObject:barButtonItem];
    
    [self buildToolbar];
}

- (void)addCustomToolbarItem:(ZSSBarButtonItem *)item {
    
    if(self.customZSSBarButtonItems == nil)
    {
        self.customZSSBarButtonItems = [NSMutableArray array];
    }
    [self.customZSSBarButtonItems addObject:item];
    
    [self buildToolbar];
}


- (void)removeLink {
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.unlink();"];
}//end

- (void)quickLink {
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.quickLink();"];
}
#warning fix here
- (void)insertImage {
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
    //[self insertImage:@"" alt:@""];
    UIActionSheet *imageSource = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"取消" destructiveButtonTitle:nil otherButtonTitles:@"拍攝相片", @"手機相簿",@"test", nil];
    
    [imageSource showInView:self.view];

    
//    [self testuploadimage];

    // Save the selection location
    //[self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];

    //[self showInsertImageDialogWithLink:self.selectedImageURL alt:self.selectedImageAlt];
    
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex{
    switch (buttonIndex) {
        case 0:{
            UIImagePickerController *imagePicker = [UIImagePickerController new];
            [imagePicker setDelegate:self];
            [imagePicker setSourceType:UIImagePickerControllerSourceTypeCamera];
            [imagePicker setAllowsEditing:YES];
            
            [self presentViewController:imagePicker animated:YES completion:nil];
            //[self performSelector:@selector(showCarema) withObject:nil afterDelay:1];
//            BOOL cameraAvailableFlag = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
//            if (cameraAvailableFlag)
//                [self performSelector:@selector(showCarema) withObject:nil afterDelay:0.3];
            
        }break;
        case 1:{
            UIImagePickerController *imagePicker = [UIImagePickerController new];
            [imagePicker setDelegate:self];
            [imagePicker setSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
            [imagePicker setAllowsEditing:YES];
            
            [self presentViewController:imagePicker animated:YES completion:nil];
//            BOOL cameraAvailableFlag = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
//            if (cameraAvailableFlag)
//                [self performSelector:@selector(showCaremaRoll) withObject:nil afterDelay:0.3];
//            
        }break;
        case 2:{
            NSLog(@"nothing to do");
            [self testuploadimage];
        }break;
            
        default:
            break;
    }
}


- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    //取得影像
    [self dismissKeyboard];
    
    //NSLog(@"jifisofdiosfsdiofds");
    UIImage *image = [info objectForKey:@"UIImagePickerControllerOriginalImage"];
    image = [self scaleImage:image toScale:0.2];
    NSString *imageBase64String = @"data:image/jpeg;base64,";
    
    imageBase64String = [imageBase64String stringByAppendingFormat:@"%@", [UIImageJPEGRepresentation(image, 1.0) base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed]];

    [picker dismissViewControllerAnimated:YES completion:nil];

    
    dispatch_queue_t globalQ = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_apply(1, globalQ, ^(size_t index) {
        [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
        [self insertImage:imageBase64String alt:@""];
        
    });
    
}
- (void)testuploadimage{
    [self.editorView stringByEvaluatingJavaScriptFromString:@"zss_editor.prepareInsert();"];
    //[self insertImage:@"http://ext.pimg.tw/polly322/1333728833-1616261529.jpg?v=1333728834" alt:@""];
    [self insertImage:@"data:image/jpg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAHcAaADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiis/WNVj0ewNzIgbnaA0ixjOCeWYgAce/0oA0K5n4hzSw/DvxC0Od/9nzcgZwNhz3Hb/wDUelaEeuRL4fOr3SosQVm2wv5mQCQAMhcscdMdeK4nxV4hh8R+HtYtRpt19lisp5PN80hc+U+N6rwRkdCcZweSKAPRbNZksbdbhw8wjUSMP4mxyfzqemxjESDGPlHanUAFcf421+500pYx258i4t5GeUSlHZgMiOPb8xbAYnaOAMlk+8Owryf4qXss1wLNb/dCoVWtYomBO5hwzg/PnBJTpgDODhgAdp4Ju1m8PQ22bbzLZQjLburqoIyMlflDEHOATgEZJzkw+Abp7nSdTDhf3Ws38ale4+0OeeTk80eAdPuNO0GRZ5w4edmSNeBCOPlxwB9AAB05xk0/hlcx3Wi6xLG24HXL4557ykjr7EUAdtRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABXPeLrdb6xtbJbmKC5lnBhLxu5yAQSuz5gQGzkEe5wTXQ1i+INck0qJYbS1kub2VGZAI2ZI1BALuR2GR8o+ZjwPUAHl154im8NT2+g6prm2MRt9rjjhjXyQd3lmJYyrIScnlugBOCStZi38MGn+JGinYbtPuYxPdMXuLuTy8EOFkYBU+QAYxyO+dp448QaT/a9jrJs4oAkbssE0YJmkDsuECng9GZlPAyuSxwPO9JQ202oPqsMktwsE0cUMd48Yt90chCA53YOPu9MH5s7sUAfX0GPIjxjG0dOnT3qSq2nTi60y0uAWYSwo+WXaTlQeRk4+mTVmgArwX4k3cmo+PbiCx0y5GoW8HlJK0m4yKMMWRfuoihmJYkc478N71XhfxTFqvjKfzZnjiaKF7iRUP8KsQhwCSMAsTkY6DGWYAHd/DvUY7m2lsLCERabYxqgLqRJJMzNvJBY7RkcLzwc57DK8E69ZaFpvia4vrnIk8SXwjhUqWHzZOORkYGcml+DuqWt5pNxZ2PnC3tQoZZUI3OSckdumBjJ6A98155oFtD9q8QXlzcwWZGq3IDyyYkf94Afk5bK7gcc5/wBorwAfQml6jDq2mw31usixSglRIuGGCRyO3SrlZXhzT4tO0SCON2k8xRI0jxeWzkgYJX+E4ABHqPWtWgAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAEZQ6lWGQeorzWQ+IFivb9Ls2cDxq007SkwYIJDoHBI+8pxySHZfvIpPpEkiQxtJK6oijLMxwAPc1xl7qOieK4Hul1KSOGyLRxRuhCtcN/qpQuQXIwdo685GDtNAHjOoQXl5oFxcmSOMxDC3VyXLq7HYFSNFZEGF5XgryFC1z19a21nb3qi0m+2fZxPGHXaAFxkFF+VMr83GO4rQ8XaTFoes2MU8Q+2z2/2glZi08cyllVEBBByyAAqoU4GML1zYvD3iO9vRHD4e1qX7VbrG12lpMMnywDjeQuCAASeBk4yMUAfS1t4l0/Q/CGiz6jcETT2MbRxIhZ5SI1JwqgnuOegyPWuOHjW70fS/DXiTVfERB1qRWl0ySAeWlux6x4UODGrAlskN6dMefSPYg2//AAkl18QNFltEFml5MVa3hBAymFRcAgLwM5wM5xV/VtG1XwZJofi3Q/EkF/4fgT7JFeCET/Ykk+UsELYxnrgjBJGBnFAHvWl69pmswQzWVzvWYMYhIjRs4XG4hXAJA3DnGORXhPxf0c3HxAtbaOWFILqNpbiOBPmHABJwGJcgAnAGRj0LD2TQvD0kV3HrOqau2s6h5PlwXBhWJIo2AJ2IvQtgEnJz7DivHvjdJt8YwpFH/o7xxR3nlkmR8knGOuNoXgAj1BOKAOz+Dpsmt7wWf2jdGqrMQT5G88YXOd2Npw2eh6H7x8K8QZPxB8Q2MDNGt1q8ysxXJRhIQpGOPvP/AHdy8Y71698EtXm1G9u980TF7ZWeBFjUxqGwjNsAG4jg8AnGSORXmGqLd3XxA8Safp0bShtWnUr5as6b3ZSVXIzznIzt/i4wGAB9DfD67vZtKeG5JeNCWjZtwKqegAYZOSH9lwFBJBA7KvIYPGkWiXdvZ20El5fjKyl2ZJZmUhSPKTKgAEhUydoGTjBz3GkeLYta1G0jhiaCGaFmAnADOwJ+4AckAKcsBt5ABJ4oA6aiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAprukUbSSMqIoLMzHAAHUk1z914she8n07RLSTWNQhOJY4HCRQnjiSVvlB5+6Nze1U38P+JNauXfWtfaxs+iWWjEp3H35mG5uMjgL1oA5zxX8So7ay1KNIrV7Xy3hCNcBJX+8CQ2doyFfb1PBz0xXkUGsXcjy6rpUGraqqSyPa2htGZbXp85dPl4zgsMlivO3hj9E6R8PvCWhtvsNCtEkIx5kqmV8d/mck/rXSAAAADAHQCgD5yg8Q+KdDluNatPAF9d6ldgSSazqts7zZGFJ8tAPLQdAoPTGSa1V+NniHSpIpNatdEeGV8eXELi3ljXP3tsiksOew/h7da95prIj8Mqt9RmgDj/CXxD0DxxJPYW5X7SkZke3kZXEke7G4Y6jpkEAjI45BrgviHo2meDYbyyhvLqy8Pa5BPJc2tthhDcIAY2UdVRmIVhnBJUcA8en6p4H8N6wUa60mBZUG1JoAYZFGc8OmCOnrXlvxU8La3ovgXVlhnOsaXJJDIZrt3a8s0Vhhd3IkjHPXBXcSc8kAHpHw1u1vfht4elWeKYrYxxs0bEgFRtIOf4hjB9we1eTfHuG+Hi7SJVZ3ga0kMKq4jCuMg8sCGb5hgDB5wOTmm/Arx09pbf8I9f3EcVqjvMk91MqIkePuJnGTvJycnGRxTfjlrMV94t0iztrhxJp80YZc5UO5DBhg/3cc9elAHbfByCFNEi+wyeTZBDiFdg86XC73bkvkHC4yQDnk5GPEtYLN8Y9Wmt4gqxanKwigYYDB+WIcY4I3NkY4Ir1v4EBoYtbgFvF5TTmVbgsWlYbiNrfKMKMEjdgkscDGTXlXi2afTvit4is9MdLUSXMrvJh+FKl5AQnzMDknHI9gM0Adt4W1Xcsdpa2dvcC6cS21u9spDbiMo7beFG1kx1zjpnn2bwxHYvpgu7UKZZ233EgmErM+McsDjGMYHQAjAFfJGjarHpu82NzdxzPMVkjZY0RYdo38kkqSxIH93rknp614T8QXk2lXV61xeQNPG9vE9vjcZDtOQnTCM4VV7vcYBAGVAPeaK8c8DeL9ZvNbsILi+ury2klZFLYO9WB+8SF5BXeD1xvGPmQV7HQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFVbnUrCzkWO6vbaCRhlVllVSevQE+x/KgC1Ve9vbXTrOW7vJ44LeJSzyOcAAVI9xDHEZXljWMc7ywA/OuC1TxX4ZvPEbnUtVtJdP0pY3hgjcyme5blW2rnftAAX/AGmPcDAB3ltcxXdrFcwkmKVA6EqVJBGRweRUteT3Pj7xZ/wllnH/AGFdJpbEIbW3iVpjMw3JFI7nap2EM4UHZ03E9Ojm8R+J7W0STU7Pw7pEjHpe6ox3c9AAnJ5x15I6c8AHa0Vz66V4iluGa68SqkBJ/d2VgkZA7AM5f69KY3guwuARf3urX6nbmO4v5Nhx6opCnPfI7UAat9rWl6YAb/UrS1yMjzp1TPXpk+x/I1yl1rH/AAnepvovh/UdukWxzqmoWzA+ZnIFvG3qcEsw6DGD81dFaeFtAsFZbbRbCPdjcRbqS2PUkZP41lfDhlufB0OqZQy6nPNeylDkZdzgZ/2VCr/wGgDotP06z0qxjsrC2jtraP7kca4AzyatUUUAFFFFABRRRQBWv57m3tHltLM3cw6QiQIW/E8V594i+KOiaedHuLi+EMEr3EOoabJGHmVljI8t1524fAznBz1Iya7TxPrS+HfDGpaw0Zk+xwNKEA+8QOB1HGcVh+BfCtjZaLFq93axTa3qyLeX9zImWaR8OVGfuqpOABgcA0AfKvi63sbbxHOtnLYvZz7ZoxYOJY7dHJYxA55Kk47dOwNJe+JTcWRgMBZy0ciysMF3Vm+d+u8kYHbGPQc/Zs+g6PdRtHcaTYzRsu1lkt0YEdMEEdKxZvhp4Jnk3v4X0wH/AGIAg/JcCgDzv4B6hrOoLqIcr/Y1sBHGuxkxKzM5KjochhncSQAuMA4ryP4lzB/ih4kkC5VLo57NkYXIPbnmvpSx+Fnh3SN40iXVtNWRtzLZ6lNGpPPJG7B7fkK5vWPgJo+qanc6guuarHcXCEM0rrMSx4JLMMkY46596APnrSoQzvdzCYxzgqba0YRtIFw5XO0hBwGzg8D3zXY6bdW97dWc0WiTvYRQxRukpKosLuxOWwTjcMF85PHUYSuyuP2cZFhItPEUO4KUUSWbDq33siT72MDpg+gqncfBnxxCu4S+H9QeMRrG7F45CqvuxwqjggDkkheAQOKAOq0/U/D0ERgubFLhL2TZcX2noyC0kTaQqoSXXBRGHQnGdo2EL61BJHLbxSQyiWJkDJIrbg4I4II659a8Lt/Aviy2Inv9Kurq8JVGntriDFuo5QQKXXCo3OwgDuuGAY+veFbC90zQIbS/EYmQtwhBAGePm43fUjJGM85oA2qKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoorN1DxDouko7ahq1lahDgiWdVOeuME5J9utAGlRXKn4gaPMJP7Ng1TVCmM/YdPlkU5GRh9oU+nXr1qFPFXia6I+yeBL9UY8Pe3sEIA75AZiPy5oA7CiuXaTxzcHdHb+H7JCAwWWWa4Zf8AZOAgz7g9u/WmR6B4ouov+Jl4veJmzuTTbKOJRweAz7279fYYweaAOqJCgkkADkk1j6n4t8PaKD/aWtWFsRkFZJ1DcEA8ZzwSKyZvhtoF7Jv1N9T1MhtwW81Kd07cbdwUjjoRzW1pvhrQ9HGNN0extcADMMCqT8u3k4yeOKAMk/EHSJi40221XVdgBJsNPlkXkZGHICnPI69Qc4pieJfE98v+geCbmEEgLJqV7FAPfIQuw79ua66o5JooSoklRC5woZgNx68UAc+zeNHsp5Amhw3Bj/cwgyyAMf7znbwPZefauJl8Ca00UzeIdNt9aW4kZ5xpd89q7bs7sqwXeOR1ftgcDFdP4k8dS2N+mkeHNJm13VpIRMUgYCGBScKZJOgz1A6454yM8nf33iQyLPr3iPR7OTPNimrPAYznaVCQrubn1dsdfUUAT2fw28M3lkmp+E4lje33xPp2qRNPCzgjdHLHLlo2z1K469weZPDUkOueOLnTJdNm01rG4XVLyzeMKonEUcUagjAZQUaRWGQflNdH4Q0lRK+sW93eKbhys8c7SSCdVGIzulRZBgHg8gg9T26C40mObXLPVklaOe3jkhYL0ljbB2n6MqkHrwR3NAHntsuo3HjjXLOK3D3UVy8FuZIy8NrFMiyPPIOjFgAqr3KsMj5qqG50u71+aB9QuJgpKS3Nohl1DUZFOGCFF3QQgggbSoPIBA5PrD20TmVtm15E2NInyvj/AHhzxmsGfSl8JeC7y28J6WguIYWNvCgy0knqSeWbvyeaAMyPxRoXhTTDs0HV7CzDZOLB8FiCcnuTgfoB2Ap+neO7vxBZi+8PeF9QvrFyRHcyzwwI/bIDPuxnIPH51yPhWw1/xKbjXHSDLSugie/2XcBGAUlbyWZW6nZkKAQNoGMeoaGkkemIkulrprKxBgR0Yf7wK8HPXoDQBhu/xBvYW8uHw9pZZcLvklumU4HoEGc59fxrF8E3kvgi6XwN4guEyrF9KvygijvEY7mTHQOrE8E5Ofz9IrC8T+GbTxLYC3uooZQp3eXOpZHwQwU+gLKmSOcAjvQBu0V4VrXhvxN4KtgmmXniKSwuCybLO7EnlyAoqYBBYbwrHrtG8D+HDc9/bHi2RJYbfxbq13fqm5rMSBGQkjbuI5XLE4Azn5QcZAIB9LUV8dazd6/ZOBcavqc0zoHublryZQNxIVW5IBBj+mcjnjbn6T4x8R6FeW10mvahHEoVlgS5ZgyZbgBty8c9emT3zQB9q0V8w6L+0R4msiqarZ2Wox7gWYL5MmO+Cvy/+O12zftG6JGR5uh6gMkcpJG4x35DdRxx79qAPVfEOiW/iPw9f6PdMyw3kLRMy9Vz0Ye4OD+FcXE3i7wF4SY6lq3h+507Tk2JcXQmik8ocJuKhtzdAABk8ck9dPTfFHiXxHZJPpXhk6fDKA8Vzq04AKkAgiNMscg5xkDtmtC08LPPqVvq2v3p1G+tyXgiVdltbsQOUTnJGOGYk/SgDymy/aTjadYr3w5xypkgu+CeMEB1GB16njium0v47aHqZUromtpEzN+9EKMihRkk4fPdc8dTj68X8c/h3a2E8PiLRrBYY5ywvgnyxI3G2THRc8555OOM5z5Xpllb3UcbXP7rTw4Vp1VyGY8iEnOAQc8gd+SAQaAPqWy+Lfg69YgahPDtYozTWkqorAZwX27Qeo5PUH2zs2PjXwvqTBbTxBpsrnd8guVDcdflJz3Fcx8INP8AsOgXIjjZbcSiOJpOZGC54Y4xwSRgdCWB5zXz98V7Vz8V/EEajnzg/wA2BwY1b39fy5OOcAH2HHIk0ayROrowyrKcgj2NPr4p0nU/EnhAPNZXVxp5kAYFlCsyZwcbux4+714r0rwp498eavdXFwb6W5tZVDRyCGMbWyMoqglQdqlvnIwFZjxwwB9GUVyng3XdQ1lHE9o8VrDEqq8oJkZskjeSeCU2NjHRgSVJ2jq6ACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoorFvfEEltetaW+iateSL1aGFVj9eHdlU8eh9utAGyyh1KsMgjBFZ9roGjWTBrXSrKFgQQyQKDkcg5xmseTVvGM6kWnha0gOD819qYHP0jR89u479Kctj4yu4Qt1rWmWDH7xsbJpGH0aRiO/de3bNAHT0yWWOCMySyJGg5LOwAH4muVj8ETSu7aj4r8Q3gc5KLdC3QE9cCIKce2eKsHwB4XchrnSkvWDu+6+le5OW68yE0AP1Dx74T0uVorzxFpySrjMSzq7jIyPlXJ6fzHrWS3xMtLqJW0Xw94h1UtnBh0940GPV5No7qeM8GuostC0fTtgsdKsbXYcr5FuibfpgcVoUActFrHi67B8rwrbWeQcNe6kuQfdY0bv78gVCbDx/eLibXNE07pn7JYPM3fOGkcDp/s9R0rr6KAORbwVe3hB1Pxj4guBggx28sdqhzn/nkgbv/e7fSuV8d+HPBehaVsuLVZ7yZi3+lSSXVx5ZwHKNIx2E8YY8AnIBbCnufEXiSLSI3t7d4WvvKMpMzYit4wcGWUjkL6Dq5GB3I4OHWtE8MXUeqeKb2efVZ2VrTTynmXjdSsssa9H+ZgqnCoDgfMWJALPhjwRq2o2UX9qF/D+hD5oNA0yQwswIxm4lXDsxAGRkc+nSu+0nw3omgqV0nSbOyz1MEKqT9SBk9KwPDfjLU/FWtFbPQmttFiRjNe3Eylmf+GNVXI3D+IE/LyDg9ezoAKKKKACiiigDndd8MC9uDqujzLpuvKAEvFTIlX+5Mv8Ay0TjvyMAgirFprM9tDIniCOCwlhUFrkS4tpAQeVZsYPDZU8jGehBraqte2FnqVsba+tYbmA8mOaMOv5GgDIHjfw3Kdtrq9vesQSFsibgtzjA2A5Oe3XketedeM/ibeHVpdIs3n0+E4ETCGWK5udyfwh0G35mXGAehORjnr5/hT4VZt9lb3emN/04XckQ6EfdB29Ce3NcD40+Ft/GJ7tby61KNV3RuhZp4SAAu6HlZFwNv7sKwUcBsUAMu/id4iWzv9Jt9Oule1EMcV41wpkZpBhmbrnlsqF6EDJwNtcdPO+maNNrATF7hmMy7laTrkyFT8xJOGfvkDILEhl5q1u0M1uRcMy+UlxPHMrHczRlgnYxsoHLNk7TlVBxTPFviEW2mfYbaCSGeQgSF3MYRUOAEDfeyHI5BAQDu70Ac3qN5d3Exm1DzpoosXAt3kLRsuAqNjOCuOgBHGcADml1+K0sdNhsbwSvqMciNM3lbdsZHyou5AwGzpyy9OO9ZiEy24WN443HBgjL8kEPuA3EcgHkDHyjjnNVVZ/OFpPIzNG4VQcbAB1Bz0GQPbgnBoAm09Emurj7Kqs0amWCKTbuYAZxnb8zAY4GM4OOtQ3lhKivOQXUEq8yYMZf2IGD2HHGSDnnFOnSKBo2kxkksUWPEbYAAA9eQcn36dabc3s8t3I92kvGVCElRCSSRtUYAx1xwM0AfcWkwG20axt2UK0VvGhVSCAQoGBjirlc9eeKbHSrWzhWK+v7qW2E8dvaQPNKYwPvt6AnAyepPfmuTsvFutWNh4c8Qaxq1pJaa7dRxHT0iRRapKDsKyZ3EodofdnqemKAPQNX0q11vSrjTr1Wa3nTY4U4OPY9q+RfFOnpoHjrU7O2ciF2w/mWogOzzAGCZ3KMY++cDg/j9eWGqafqizNp99bXawyGKUwSq4Rx1U4PB5HFfMfxPv4r74mXhlMkd/bSJb+TukZHTcFCkkDaCDv+XA+bAyTkAHsfwnvZpdLu7OUwEQsHURg5VWyQCTywAAAJAzjgYrwj4qmVfix4gnDqJY54tsWPmYeSMMByMjA565IOBzj2D4JaLbW+n3Go/a/Mu9gtmgIAMe0ksT3zuJXk5+X3wPHPiZd/Zfip4ht2lkW2luP3hjOGOUQ4yD2IH9RnigDNtNOuLZXtoxBL5jhrpt+5/KBVieGIKA/xMMHAxwTXtHhubSbHUdGsLWweTUEmx9qt7v7P5UQKfLLhisiYwAFJDY4VT08XSM2KSSXhkuQ8gubJoSzeaVHzI7kBgNvqNwK8ABsn2/wkulax4KWfSruCfVbCPbdSiKbhCrDzETBfzGUgkxsrMwILcYoA9gByARnn1GKWsTwoL1NBgjvbeSHYMRCYgSMmMguoGEPX5csQMZJOa26ACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAPJNdnvJfGNzpWi27zI9wJru6aQFri5Xa0cS5BAWJSpJ+6mQTlsK1dfDtvP4hk8N6NIX1WUGTXtbQ7ntI2OfIidiW3v8AdJJLY5OT06jxrqK6M7Q+HbKD/hJtRVYUnWIHyVZ/vv8AUnj1IychTXQeFfDdv4X0RLCKRp52Zpbm6kH7y4lY5Z2Pc9uewA7UAaOm6daaRptvp9hAkFrboEjjQYCgf5696tUUUAFedad8WbKfxXPo2oWMllH/AGhJptvcM4ZZJ0dlYHB44MXbqx7c16ITgE+noK+ZbbVfBi+D5LzUNThOpX91c3b2rRNK7ZlYIQcMEfbnqBuDc4+VgAfTdeU/FPxDf2H22SPzJdL0yGEXNrDcvAZ5J2ZQHdMMEVVzgEZLjJ4IrJ8HeKYde0kmTx+NGijIht7YvCrhlIwf3wZimGUYLHPPOK0tdguL2Oex1ieJ7trGKCeVZFjj1O3VwyTQM/yLMrk5Rsj5gM4INAE3hHxZdRaaNVCztoUbeVdq87XKW2CQZ4rhiWePIyytyucjjr6mCCAQQQehFeN+F9Cj8GeIrjRNOM17HJeQ213czJtyssTu0RQHDFcK4cAgB2XPUV6N4KleXwdpqyKwMMZt139SsbFFJ+oUH8aAN+vIPiF8KHn1c+L/AAs08Wro/mz20UpUzHnLxtkFX56ZAOOx66HxGvvGGl+I7SfQdYS2gltSsFpLArR3VwpYmPcx+VypBUcbtpHUAVj6d8Y9e0u+Nn4s8NnauS91p5+VAASSyse2D3HQ9cUAePx3j/2rfI7pcIczx74T+9k2ZIYINoIK8jHLZzu61NqJsrGdYp5T9tLF7u2jPmBnJYglmJGNrFOefmHvXcXvw5utd1HXfEHg2ZXia9Y/YbtDFu3Ro7FM42nMjqAQMADBz0851Pwn4l8NQLPrGgXvlzjLMyFkVQchSwzj5hkg4JwOeTQBmatGy3kFp5BjieKOVY2JMiEou7nAxnbwDkAEDPANUnOyfbbxqzABQmASCeCp4BY+49TWroHg7xB4v8xtD0w3MoZjIwuI0478MRxz/P8ADt5vgD40aVbh/wCzJAxUtCt2wIGORkr+HU/j1oA8tjWd0A8wqI22AMfuEnI2jrnIPQfzrs9L8KSv5N34n0XxTMsjbYYrLTSGuDgbcyuAcEADGCe4PUV6RosXjbwkiw6J8KtOgKDJnacTSseed5fPOOn0HcCumsfiJ46t2D658Or0WwwGksX3uvbhOS30BoA5XRbH4YeK7+HS54dc0TXIh5cP269kWYMOylmZQQegwM44HUVQ1HQ38C65pOna/pVrq+mIRZ6d9umYWp8xwzSZ2t5b5xuVgRjJHHFeia9D4F+J9kLGS5gg1hkBtpJozBdRN2ADAFhk8jkc/Q15r4luJtY+EF1qHiPUftmq6TejSrcxHKxyrIpeTcT+8dkXrnpjgZJoA9q8K+HrzS9U1bU7tLS1+3iFY7CyJMUAjUrnOF3M2eTgcADtXzB4jV4fGOuRTTJexXlxIGMoMflybmCsygjkfMBzjnnB4Hr/AMJPixqHibWo/D2tCFZhaboJgGLzuME7j0+7k9unc15F40tYLH4h67ZkmK0YtIjTzliBjejRsAM542jkYb15AB7B+z9Ywro+o6inJuHVRjDbMAbgWxnJPOCffHOT5T8Ubd5vjNrNv56R754zvkbCr+6U85PYHtz6DoK9S+AE9zb6de6e8Bis5D58GdrEuPlcFh1OAhxgYz07nyf4tqLr4t6+MtHh0wGQktiJBwB64yM4GPSgDG0iya7gvYrJBPcJC0j3UsvlxRocZfcxGORt5ByTwQcA/Qfw0bSPDPhS11XWLKLRb6aIwKDMzCWISMygAk/MCWyOoHJxmvm+3WEXzNbyqFUeUkLszhsggkthRsJ59fmHB5r0PRJbjT44Brd7p8en3crQyyMyjYMKF+XIyu75iqLwAwJG4igD6Zl1OCKxW7KzvGxxiKFnYHoQVAJGDnOemOaksbv7daJcCCaEPnCTLtbr6V4rpN7q3iK7i0Mru06AhLeWe4hfcyAo7fdbcAFzkpgkZ4LAj2Wxht9M0mGMLb28MUYLeWFSMHqSMADBJJ6DrQBdoqrb6lYXczQ217bTSqu4pHKrEDpnAPSrVABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVT1XUrfR9LudQut3k26F2CDLN6Ko7sTgAdyQKuVzWupHqfijQdKkIKRPJqUiddwiARAfbfKG6dU68UAYGmaPczeL9Fv9Qmkh13y59Qv4UVZIlR1ESRbjyuwcAr1xIf4jn0SuC8Hs+sePPFmtO8+y3nXTYUZ/kKxjJIX6sSG/2yPXPU+INct/D+lvdzDzJCdkEAbDTSHoo/mT2AJ7UAalFYvhLUbvWPCmm6nfeWLi8gW4KxgBVD/MFGCcgAgZzk455raoA5vx/rcfh7wJrGoyYylsyIGBIZ2+VQcepIrwf4aeC7CPTI/EN5d6EZJDtifU5wYoMH5v3QILsU/vFdu4Hmu/+NVvq/iiK08KaFD50yRyandqHIOyMYRcAfMWZjgeqj0yPEtF0yLxJ4SuLBrxo73TZWlt4ZGRE2MhZ+Mbmbcg/AD2FAHoFh4q05tW8Q2UWl6H4i+wxAaZKdPhj8yfcMJEijmPOTwSTtHJ3Csu/wDiPdeL7rS9M13wva3FjDKkot4S1uYcKRzKThV4YngAAYzwccf4LfXLPxvZXVnZyiWwlKS+TD8sQCkNuxwSAD1yTjvX0T421u1i+Hesapd6SLC4nTyHhvIV33Axwvq3Bx7EHBwM0APt/GugarrE17pWnWl1dWsavdXZ2q6wksAVYj5zlVwuRkOMHqK818DfF+68NajPo2s6ddSWE8jXMBZ1EtuGyzABiAyE5IGcjJALcVy3ws0caqdddo41snNnbESKXIaS7jKj3+4c8enTPOx8atGvNG8Z2+rxpshaQGJ0OCTuL4XJyfvHI6DjGAaAPXNb+JPgK50k2utTSNDcx5NpcWMqu3TgAqPmBPBB4I4NUZfBWo61pUsxu9QsbR4xssb+c3bSIMkeZjLdOg3MRnPXiua8eeC/DV78Po9f06a4Kho90zRgyPGDgoMKACD9BkYJ4GNn4J+Pf7b0pvDd4W+16TAqrK5XEka/L7H5eB06Yyc0Acl4S8c3Xw512DQdSuJrjw9KxjhEy7WsiWXliRnA3NkH1U8Dr9DArJGCOVYdx1FeLfE7TtH8V6W+paVMyXylZlaWErGyKQBMSw+VOcA9GwcA5yNzQPFEd38M9btZFHm6XBcW52FkVo1XAbccFODjn5vlzjPFAF/xT8IPDfiGVr2zR9H1Xqt3Y/J83qUGAe/TB561z0finxp8NLgW3jC3bXNBMgWPWbcfvIwSTmRepwB0P4Ma7X4eavFqvhSyaKya0QRBkTe8gKknku3fcG4ySBjOM4HRrdWV4JYFnt58fLJGHVsZ4wR+lADdN1Oy1jT4b/TrqK5tJl3RyxNkEf0Pt1FW686n8C6j4Y1SbW/AM9vBHMubjRJsi2uD/eQg/u2x04x9BXR+FfGOn+KreVYle11G2Oy80+4wJrdxwQR3GejdD7HigDR1nQNI8Q2q22r6dbXsSncqzxhtp9QeoP0r55+K/wAO7/wvZPcaXfyy+F/tKSy2rS7ntZGURg+pXbhR1wMD3r6J1WTU4rPzNKgtri4VgTFcSGMOvcBgDhvQkYrxTX/Flh4o1u+3C/07S7vTYrK+nFm8qrMkshMDMqkdTjeueM468AHidpdLZX++1g2SxhvkSUvuBA6MuQTjPUY65rpkvp/EOpLq+o/2VBMkKQW1q0JYfJhRuQ9tpBLA54GAcYHHSXcaadFbW0twMktMjHCMxGM8HnHP+c1YhlFlbJscOWYHy1cMrAMyksRgp1GM5OO+MUAfQXwUSyn1PVp7Vrhvs6+Ur+Z+4YMxYlBk7vm3ZJ4GOC+Sa8n+K8UafGPW1uLp4F8yNxMiFipMSFeCc+nI/Adq6z9nq+uE8V3cE07olxan5GyfOZSCCcg9FJA5Ax2zXH/GJAfi3rqrGUJePKyt38lOc56HqPqBigDmLWE6h5rlAEt4XlYEbnZcY+UAAYXr2A5PPSpiyrpwd/s5hhJCQSDZIfnXdtK8tzn744A4FVlhK2sjeci224pvDZIfBODhckH6Y4HPFaGo3NpPotreGYy3cgaGSBVVYolyDhFGNp6dFK5JOSTwAdZpPi3TNCtJp4prW6R52VbYF0eSMc7GG3EcBZd21DliwDArlR6ze+LNU1eyFn9p063gNrFJKJlCeYGGWRz5yiIhesfzEDkkg5rwrw1cwQ6ZIA9ugaTzPKa6KsSm3BIVCwOSSCGUHkY656Sx1Oe41uLTtPjkuIJUk32sJEK3UceCT5QyPMwrNuDOx+uVYA9z8BeEW0BZ764hjgubhQnkRszKig9dxdt2cA9v1rta828BQavb6ikd0mpR2xjDws6bonh2n5CxOFwxBULzycfKQB6TQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFc7fRiDx3pdyHVWuLC5tgGz8zBo3UfkHP4V0VVb3T4L9rVpg2+1nWeFlbBVwCPxBDMCPQmgDnfh7praZoF1G8yTs2oXGZUBAcq/l5x2+52rh/G1/Jqvh+/wDEMToW1EnRdDDH5RFI22WfpkF1VsHsoH9456SW6S38LyaQ94LOfVNQvl852CbIPtDtK+45A+Q4DZPzOv4Uke08SeP9MtdPkhm0jS0AgNs6mMCMI7EbePvm3UdvkcD2APR7O3S0soLaNQqQxrGqr0AAwBVXWdYtdC0uW/vGxGmAFBGXY8BRnuf06ngVoV4R4/8AGVt4p1Ce2srlZtB01WF5JCnmbskBmyPugn5BnAYF/mXKmgCpoV74j1LxoviTTUefUNas7wxRTEbIbJHiSF2U4z8wb65B6ZJ9J8PeF/DkKW+n3tppr6zBm4eISB5h8wy8hBy2W554Gdo4HODY2ukzWsfifSNYuLVtO006bc6fZyKTIsWSkYZ1BjJPoAcnHBznzTW/HdrZ3MqaXodhZatPMLqy1uM/vSDjG9nJOSQytucjOcgjNAHsWreG9I8E6PqV74ft5bbUb1PstlBDLgfaJThSoPctgknO1V4wBVL4k29qnw9tbSWaTU7jTrm3jf8AfqzvMF6y7jjnO47umc8jg+b+GPjRrMerwWtzbHU55jsK31wqiKYs2WjZY/lXadpXB7Y756XS/il4Sm8Oa7pt3JH4a1O6nneRooXukZ2IHmqQMMcY64HAwMcUAafhzwtY6Lb+FtNs7WKOe/v31S5kPyusMQyoHfbuaEYz35zzVz4kT6X4m0zVdKOy4ksbaWaN4bhQA+ACG4yCCfUKTtGS3A8p8b+MPEieI9C8Y2L3A0yGM2+m3rpj7UEYrIzj+EuQx2kD5cccVHoniuXWZ30/7NbWk19e7zZ21t98s2QTuON3zEbmyMemACAegfDjUZ4PgdK14gu5Jrh4baG5ueZQSoAU5yuOSORjG7gc1xPgO5bwn40icwW02nSNIRNEASrFGAT5sYPXOSAF3E42kDo7zVtM8J+CLTQ9Rv7Pz9OvJ9trFKpcKGwmUUZJ3Eks23gM2CdorhPGt2fFd/cXthb3KxRiGRI7bTNkYOw72DHDA8ID6kcZCg0AW9V8dXyanNBpUgu5POZld1O2CR2ILuzj55VJIV2+VQflUdpR4/tLDwpLZtG0uoyQTR28KgSRRxyDl2cgEuTvdsdSeoA21wj6DqCzwh9luZozN88u4jadm5tuSNz5C98n0IJpzwxW9sUm817sqpTcy7ET2IJ3Z4x0GM+2ADp/B3xK1zwlp8ulacN9tcFiU3tvDkYBTqFPQ8DnHNQaI91qupwGcQ2sNtPuuH+VJJpGP8RYEseuMhgvPHJzR8K6Nc6pqltIiNFbK5R5lLgucElV2qzM5Xsqk454613fh2HSLPVpFvo9Ktbi6JitI/sU00hA9VFwAo653sWJ+nAB6r8NtY077XcwBIrJpdqQJcskU820kZEYijJBz3LHjtnm78QvDOoiWPxh4WZotf09B5kak7b2BTuMTKPvHjjuc49MY+n28ltHD5TefG0ih7u0+1wguRnP7p5k3YAOTxggcYr1gDAAyT7mgDgtW8YLrvwZ1LxHosjxyvp8jAxsweCTbhgCMEFTnn2z0rqfDUelxeGtOXRCh0zyFNuUJIKkZzk5OfXPOc55rzzwpHa6B8T9e8MoVm0PWVku7WF48xpMrbZ48EcjOeBkYUD1qx4j8K6D4StEHh2TV9P1W9kMdnY6XfuPPlOTzG5ZAi8knAAAPsKAPQrzRtL1D/j902zucDH76BX49ORXI6l8GvAepsztoSW8hOd1rK8WPooO39K4jxf4t+IPwxtNJl1LXNK1j7TnfFJaFH3DBZcrgFRnhuD7UzTP2lLF0xqvh+5ib+9azLIDx6Ntxz70AdZpHwmfwneSz+EvElxpyzY8yK5tI7kNj3O1sd8A9a4Xxv8ABXxhr3iC71yO/wBKurm7ZRIsYeAKAoXIBLdlGeT1Nekaf8Y/BGoR+YuqSQR52mS4tpERT6F9u0EjnGa67TtZ0vWEL6ZqVpeKACTbzLJgHpnB4oA+TL34XeNdI0+5W78N3D7Tujltisxz90jCNnBBz0zlRxjNYdvJaWNvOl40q3TptngmQo6MM8jjJBBAwSBnJZSABX27Ve6sbS9TZd2sM6f3ZYw4/X6mgD420nTNTu53uVtY0Uwkz+QQu1c7/wB4Qf3SkHZgFDjA6dfRdK8S6T4Z162u59P8y9ORDaeUPNVn2E7mBdiM5IBZmyAfkByfW7v4V+Crssf7At7dmUqxtC0GVIwR8hHBFc8vwQ0fT2c6LqM9skgIlgu4kuYnBBHQ7WHBI4bnjPfIBe0z4gXt1YSzixkCb8/adRUWkY3D5UTqp2ngguG+V844Fd/bSma1ilJQl0DZjOVORng9xXE6V4f8X6Narp7Xul6pBuyL2UyQTxnbt3KuJEBHbAA9RyTXXaZp7abbGFr68vCW3eZdOHYe2QBxQBdooooAKKKKACiiigAooooAKKKKACiiigAooooAKKxr8+JJL1o9PXS4bQYxNcGSSRuBn5AABg5/iOfaqx0DWLmbfe+Kb3y858mzgjgX6ZIZuw/i9fXgA6EkAZJxWXL4n0CBwkmtacrkhQhuU3EnoAM5zVL/AIQjQpHD3ltNqD4wWv7mS4B49HYj36cZ4xWtZ6Tpun7fsWn2tttG0eTCqYHpwKAM+XxRarIiW9jqd3uB+aCycquCRgkgDqD+VRNrWvSzeXb+Fp0U5AluryFFB7EhGc4+gJ9vXoaqXmqafp6b72+tbZOTummVBxwepoAxnt/GN27Br7SNOj3fL5MD3LkfVigB7dD6+1VT4P1S9x/a3jLWZgFACWXl2a57nMa7v/HuPfrTm+JPhMyGK01VdQnDbBDp8T3Lk84wEB4J4z0yRzzWbN8TCbe6ubXw5qC2ttN9nkudQlis4/M4wo3tvJySCApIx0J4oAs2Xwu8OW+pS3V3ajU4zGqxRaiWufLbJZ3zIzZZiRnAH3axfhfZG41zW9UZEMVmx0u2lijEccgDtJKVUAfL5h4P+FV5/iB4qubOSSNPDmksxYRC6uXlYqrbXkzhQFQZYk8dF6nFZTeO7OOyGh2R1EaRalftN3CDHfX5ILO6qQDGjMRukyD8xxjqADp/HPiqFrW4tY7hI9KizFdzCYIbqXIUW0R5OMn94wHyLnnOceK38sT+KNVsmvbbULVpjmTSiYkm3xg7AqkmSNeUXkDjqM1y8iQar4ne3vbW10+IMwaNCU+zooJPGQpPUnHc/hU1zZHQ73SdSg01o1nZryKOVmwYS4EXXt9059W/AAHXwarNYafPpRvLeExwiJJVmAAQkNHNn+IZ2hhzwd3fjk7Wys3XVE1pLrbZxbdkTRxNHMxJIABIZd2PmI+6ByAAR2fjbwZdeE7O3mCyyWTK01pdOh8y3LL88D7SVO45wMnIJHqRxEGq/apY4rlZGwdxggwdxiHAbHbZkbvbnODQAkV4WuTpeow2dpbQ28qbJI/mg3D7xzgs+No45+UEAkYPWeD/AA1NqFmt74dlihY3kawm9hSWOQR7Tlw2TGN55KnkuVIG5A3MeJ/C502+vbq6uWaOTLwOABlzuJRx/wAs3XGDH9SCQBnpvDtxb6N4AsdTjuo1uFuir/2cn+lIuCT5i4wcdQSQSHI3BRigD2LU7XVPE/w61zRPE2iraX1raeYJ0w9vNIAXVoyvPBA3DA6kDNcl4H8O/Dmy8DWuqTCa7v5oCJ5U85JlkyFdUCkFcMcZHXBOcA41NI1DxH/aNv4lsvFQvvCdzKjTKVVzAmdvllHYurE4GQx5JyOlVfiD4lk0bUbm8t7hIZslYwmo+W0qqzbtoki7bVyEYZZuM8kgEd34l0DwxqiQeGvhfcXl3FFueZLT542PO0uFclgdu7nKnIPIIrjrv4pfEC4k8u30q001ERpI9tl+8ghDDIy/YYHbnP5cxrHjGHVbG3iN1eyFC8rw6hO8yFuGx8p53cg5/HFd/oPinwBrUVh/wlHh6GK42BFmmRhEsYz8+4kDBJYYGeRx0AoA801PTtb1kQ6vrM6yNPHIYN52S3CqcZAAIA3HHOOc9zk400HnxQeWzTCCIy3WVPyNk8M2M8gKPQEgZzmvW/H1lb6NJY/8Izc6Vd2iSiVbWOcM6ykbTGqxKAVKn+JjwT+Pm1tE0njeGHTSk7zTo6lwsAzkPweNo/75OMjANAHR6FpcxghSaSztr7dsgtL6FpESI5IjKgEmRiCdqqS2RuwDg974T/tR2EdvFbpFuYXFpNpEgeKbIJBcWu1SBgbQOrDvxVez1OzigvtRa4SwFgjPcyIis0b8YjynKyOG2mXO4coh+81bHhu0j1XR7TVJvDMVnHd7pIltNNmkIiJO1iyTAhivPTJyDznkA6zw54SV71dQ1Gw0wFfmR7aJVcsMAElY42XAAG0g8dTmu8rH8N2wttIRVkndWYsBOZdy89P3pLj6E1pXUksVnPJBGskyRsyIzbQzAcAntz3oA8Y8YyzDxGVsdQFtqWk+IbdY7sRhhDBephgQTtOHU9SAccgdT6TofgvT9Hv/AO1J57rU9YMflm/vpPMkA7hB0QcnhQPxr5/0/Wn19vEupS2X2aWbU9LE0TucxSCZ8hRgccEc9PTnj6koAw/GGkx634Q1bT5FhJmtZFVpiQqNjIJI5GCAfwr46l0z+z7uSyltj5pSNRM6yAhmbIkQYHykdCRz2619wNjYdwyMcjGc18aa/qq3vjzU76ZUF1NfGaKRgXdBuG1GRDtOF4I5OeM8HIB7b8CNOittC1B7oq9/dOsrq24sI+du7+EchvlHI5zXj/xEha3+MOsJpFwljsuF2TK4t1jby1J+YYA5B+p9TXrXwJWSRNSu5BOpmSNyrzlwW5ByOgPygAYyowO5rx/4vM0nxU8Qk7w/moNuzGVEa8nn2B9+vFAC6d8TvHmmSTPF4klkW2jUFLh1lV1yFG0MDnqDkc45zXbaD+0Fry6rbxarYW93YPuDSQwGKU8cH7xXAPXjpXldppTTC0git455pGcTD5jtw2ACR0+qk8H2rRsLzTIkit5HSzuC6tNO8JmNuyPjnIwFxliqA7s7cjpQB9JwfFvQEvhY6vDeaTd+WkjpdxECMMC2WI+6MAdcZ3AdcgdvZ3trqFql1ZXMVxbv92WJwyn8RXi8XhqLWdHg1KbS2mjmi3wzJGZYbdSxVfLhBLzy7nJ3SYA356KFrpfAmlL4Ok/s7Y8TXjKZFnZGMcpB6yfKuWABEKAkdc4zQB6VRTI9/lr5hBcDDEDAJ9QMnA/Gn0AFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFAGF4h8Y6F4Xj36temHpkJE8hUE4BIQEgE8DPesP8A4WPJeCE6L4R8RaisuCJWtfs8YBGR80hGe3PTnrXcEAjBANLQBw8OrfEa/VdnhjR9MyOWvNRabHTnbGo9+M//AF5ZdC8cakh+1+LrXTw/3o9M04fL04DyMx9ecCuzooA43/hXkNyCNV8R+ItSXpskvzCuPQiIJnkA8+gqaH4e+C9JAu4/D+nh7dQVlnXeRtxglnzzwOTzXWVl6/pjarpvkRpE0quHQSsQvockA9ie34jqADgdeje41bUG8PTwfZ7m0Vbry3EcsKRZDoqnBAwy5wCcqVOK57TA/jXRrW6022LJpMcsK71ZWLSFWztwMNgsC+4jKtkjeSOyu/DU9t4NvkmtrB5kjWRLVFKRRnPzK2D83ykg9WPqeK5jRbD+zvCOtz31hutAn2c29hcIqh88FFLYyM5Hc7hhWzQBzmrPqOtW9xa2l08kmjec+6ymGHXYmAigcgYONowRuxtxmsaHW4rHTmlh1VrW7ihKQpIJPNtiMBg5ILfMdpGQVHALYJA6vwxaz6ILnzIZJfOTFzai4KBE3lSrMuFJ29erByOckg+fQaXZWMtyourgX0krCdVjknMUav0YBQ6sPlB3YPDeooAh0Fo7+3j0ptrahqU0dnbmNcvC8jjzZWG0YJGPmIJI4B+XI9OvPCltrXxdfR/LMumWttBEYQGj+ywogBVR1wxC8ggcnru54H4f6NJa+PvCksl+k9vJeMVG3IRwhbDYz8xyuOvOckYr6vwMk4GTxmgDzvxzGmvwz6DcFZkSTElpC5jLpgOOowWA5A6nYSv3WU/P/i7To9KuUvtOUKsYVWeaYSvIDuCDbkkAR7V5Jzjg9z9M+OrCC+06GIukd5K/lW7OgZWYjPlkEYIYheCRyAQQwGfEviezatYvNbGOIyMHltNhfYQSSynohOScgKHAbgNvFAGBrVw17pmi3UjtBIUBbUpHZiZI1VgqkttZeScckHoAchuTtbzU9Y8SNcLcBr+8cu5TZEJXPJ4wFyT6jk+5qEIbP+z5/PihkLbmRrf5owTkMQRiRSpBB56kemZoNOktL+GdL+0GZcRyC4ERVgeCVI3IOOpAHvyMgHtHhO1Np8MLrV762iOvjUoEDyQK0yEXEaIJIhzvypI3Atzmk+MB0STWruxkvY7jWZYMwRGIN8/O2MlHUhgCdvmK4O7APpfj1K5bw/q91pvh2zsruSBJrIRXUVypkiPmsRtcgodoZcKAT26E+Ia3fTeIbufVjapGrQoJzY27eWjZ/jJAwxx2OOmDgYoAgLF4l0yayiFw9xiS4ZAWVjjhSuM+uD/ia6pdM1PwHeJYXmrwrM4877Ml6VS3kGGRm2tgNtyQGBBIx6Z6Hwhq+m2eh6dpV3pnh67v7hTIt9fWjEJC3DCQsq5AyeQ2DwPp5z4o0m3tPEdzZaTe22rIvzmfT4WEZzzgDJGBkdOOcUAeq6L420M+VZ6va35TUokGx5DEqrv3CZijcleowFIXnnOa8w1SW20nxu1/pEltJBZ3iTRy2+TDkMCuBgemcD+lY0V+7ajBdXX74RFdyZ2b1X+HIHGRxn3r0T4g+INK8Q22nQ2FrPZW0bDztNtoI8QyHgYcIM5GeCSct0HSgC3b6ZbeLra8t7CeFJZ0N5JDGAsG1ImAAVQPnAGQGO1fm4ydtd78KPGyz6B5YXy7O3IhjtIYVLNKVLFVO7cdxPGeSc9QrEc54SsbL4f6+vh/WxFFeyI0nnBJHO54wBtBULIi/OCB1I6Eha5q88C+I/DN9puo2gjmtXu45dPntwVEhKhgxBX5QQQuGGWbgA9KAPqSwmuZ7NJLy3S2nOd0KyCTZ6AkcZxjOOPc15N8V/iRLZrJoOgXA+2Oxtpx5WWZ2wAi56deT0ORgnBx6jpOnf2Tpmw/vLlsyzMCTvkPLYJ5IznGcnGK81k8LxeFdP1P4heKfJ1DWkhNwlqUVYIZuAu0d34UbuO5AyaAOOTTbDwp4Q8PaNqF3aG7uPEcc+sOJsi3ZAGMeQOCFKggZwSfWvUtQ8W61f6vf23ha3s5YdMs0u5/tkcga5LhykceMbeEPzHPJHHBrzXW00vS9U8KnUtHk1mzgsJdW1COGLcrTXTD533fw5BxvI4AyaveK49Ig8Ey+KvCN7MujveW76vpiT+UW27VChh88b8qCAeQ2R0yQD22yu11DS7e8SORFuIVlWNxtdQy5wfQ818d679stfEuvxWzXMa2cmWWCdUMRV8AOwH7xl3EEjktk816P4buIfEGuQax4YhbSLe106V723TU2uJ58r5YQKzFY1BwQz4x948AV5RdzytrV6zRWRjmlmjVGfMURIHKuDg8AYbcdwHvQB7x8ALi3bTtatkEhnguceYcMrRZO3D9znd04xjk9vMfHi2kfxk8RS3RZI42LeWGEbSHyhwCxwAfrk54HOB6r8CIlm0zUNQS3TbJ5UYnXGMhfmQZO884PPHIA6EDx/xg0tv8UvEwmdx+/mV1jZjvjbAAOWyRgqcZI+XGMUAZ8/iRDp8UFlH5E6gqsUNqgEzSMdzMxJblVQYxyPTnd2+gquoPBYWGiS2urxW6z+WYV3SsQxdUcgx2ilYz1Us3TPc+fFYNWuJv7LtJLaNVWW5jmuAgDjdkrhQqrnYAMbsnGeePS/COuRk20epCZbeKYN5SAI8j7CCGjLOZcDDLnCgAjGCcAHcab4h1XQJdPjn0XUYrYozXErAASE72O55jv+ULK2MKTxgAdfQLC20rU5ofEEUHmXE0KqksuS0a/wB0AkhDnrjGSOc4rnfDWq+HNe02C1kEflWqLFHBdvEu4MAR+5U/LxjhlU/N0xXXWEMMULvbyiSOZ2m3AgrluTgjtnJ79aALVFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQBUkWKSWWGYmeOYCNoWQMijDE7uOh5Bzx0H1wvFuk6dd+ELi1kvn02wsxvZoWCqAoztPB49gDzjg9D5vrOt3fhnxfqt/fTS+VBeTXf2OOZkWdRGioC/THzJ9CCCPlBPDeJfF/ie98N6Po17OIVCM1zAtsU8zbsKF+csB7cZHIIoA3/F+o3vgrTIodOmWO7lYvGmMzQqUWNSSQdhIweCDwMscgDgra5hmlzqEkiQxbTcuHaUvLnIYADPOSASSAQOOBXRGz13WrbT99wNZeSNYoYbibm3jIICORgZZDnBGVDA5yRnm/GX9nmO1S3jztMpYurRshwMIc556MQSedwDc0Adh8M57e9+KuhwQvIotftUpieJVbcYsBmI6kg45yRt9en0zXy18GraC2+KOk7GkaZrecys/f8Ad9QPTO4ZzzjoCDX1LQBieJdKl1S0hWARb0fpKMowP8Lr0ZCcZGc8AjkAV8++PPtB1KzNncxsrXH2e4dpPO8uVl+46gfMxDbg4/1m3dgMrE+x/EjxZb6DpMsBtLe+nWNZ5LSYdYixG9TkcqQTwcjGeOteHWEsdze6zcX1jBd/6OLy4vioxNjcSwCYwGDICBg5XI2tnIBwWuSFVsbMnebaEpvyDnLMQAw5KgY69y3QYFbHhvx7daBKourCz1aOMYie4UrND1H7uYYkUc9M4+lc5cTNeSTXs0q+c8pY7zknv0x+tU6APbdW8YOthPqN14J0+fTb+zjKyNYiWKRm4AFwgUpgqAVbLBgRkYBrz/QPFsmgLNp95pFk8EswlYyWwE0PXhW64wRw2fatz4d3uoXOhatYW09wb2wiN/pkWQ0bMpHnIUb5WBBUkdflyOtVvFTa/wCK7ZdcurDTb6S53f6bYQSIyrEcEHopzkHoWxgcYIAAtzaaLBryA6nb3tre4gd5Y3jSNN4y5ePIPRiQCBgc561Z8QL4Zsyp8F3unqqKFe7kluIZgx4+XL4Kk54K5wB1AzXH6NrK6bI8rabazxkxiTcrbgoDBgOdo3AkHIOe3etFf+ESlspL6SPUFYyOWt0hyIyx+RPN3BTgKxB2Dr0OOACO1n8M/YRJrLarc6hDIVFvAyeQ6hQAfMPzYJHIA6dDWz4Rv5fFvxJ8N2MkK29jHdRMLSBf3eIxuyR3OFwSecZrmZ7jSbtDK0Ulq5dQViIYbeQxCYABxt/i/H06L4T+WPir4dIkST96wwYwAPkfrkjnoc89e+MEA91+K3h6XUtQ8P30LiJIZpI52SPLMCo25bgBMggliBzjDZCn0ayhe2sYIZJHlkRArPI+9mOOSWwM/XA+govLOG+gEMwO0OrjBwQVIIwex46jkdRg4NTjOBk5PfFAGJ4svbiw8O3lzZXLQ3cERmiCoreaR/B8wxz07HkVwHj7UD4gW3ms5Q9gPDN/qJjbLKSyKImI+7kHJUnOMMeOtavxP+z6vogs4Lu3M0qTxxwmRizyKASoiztlYYHyn5hwwzgq3EeEAt98Dbi5bdNq91GdDtmaPb8kkgRIl6BgC5Yt1656UAb/AMFdUstVhvb2e9hOoXEVvZx2zy/vDDbxKu4qT3ZnP/1q5n4p6VongnVtQMUR/s/XtOnP9nqxEcV4CoSYL0H3iR6EN24r1G1+FPgu2s7eAaJCXgVQJwzJKWAHzblIIY45IryL4r6Dq2mapa6K11G+l38wntr27fJiWJCot2LHkJuJB6neepHABwPgvVZtK1ZLaSVoba5jKTI8nliZeT5b8HEZbG7uQpHcYg8QSWyazcPAtmbcTB9kKgM6spJYAcKWByV6J8q9QRWfJbRaM6l7jNygLYWIOhcMMLlscYJz+XNRWs8jXMt0tzGtzPIyPJkoqBvvPheowTkY4HY9gD6B+AiG2h1GD7AUBRH+0ozmNh/CoJGCeWJI68DqCT5L8SPO/wCFteIfIkdD55LBDyyhVJAHfp09q9a+DniC91XxBeWzXEkOlWtksFnZPn5irAtIM98EZzz846DAryX4iyQN8UfEjmMyAXJKTRy7TGwXqDyDyOeCcA4oAy7C31GW4iuUjEXmqYzJaW291B3EkBVySOQcEdQp4zW/odmdWZLO+eWRYISMrlYgxkJDohT5mDBlK5XJGc7EY1z51K+1l/7J0u4uVjmIeSIMwSSQcbgoyRxluTgZPTvpaVfvHdRqkdmbUxbZGmUPEkb/ACOxLA8LhQDtO0gYzk5APXvANlbz2NlJq73Ext3czaj9rtjbJKsigABc8M2AGPLFCegFei2/jXQrq+Wys7gzztIE2Rpg5PU4OCcZ5xk9fQ14YvjF4Xh0TTXgv7GeSS43whoEuM/KsPCrggZ+Z9wOOh4A7XQ9C0DWIPMN7BDPa+XO5eOPZHknco2EISjcAqPLJx8p+agD2GiorZZEtolllMsgUbpCu3ce5x2+lS0AFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFZer67aaM9sl0SDcFwp4AG1Sxz+gwMnnpWpXAeMvCU15ria9bLc3Uy25jCGY7bfBB3RoATuPUnkjado3FSADK+IsGh3usRyNJfvq62oMIjmVYtmWO3DZ6kHOByBgkVwHxAhs9O0fTYtNufP1USkS2g3BDEWUlGGRjbIxUgHn5s46C3qaQ6F4quLzWL230xmEU0kUrrITiMKiYALEqAQQoYcgMT1bndeSbxLcSjw/pmr6g7tGkUn2NzEvAPRiRHuIGSDk4z8vQgHPz2Uw0qC0vIWgVkL2XmReWF3PkzAA7sMqjkBshB26Ypv4fMEdt587upMzSyhVb5WJXkc4LHknkcYFd5qPw31uPRBrfiaez0OJHklke6uTLNIW+6gjA+8McYbOGHocX/h78FpvEc7arrIubPQnO6CFwEnuRnjIH3F/nxj1oA1/gFaHUvEup6sxkkisLVbWJpiC25zk4I7YjxjoAcCvoKvJPGeq6b8L9GisNBV9MicqrvBEjsuQ3zDfy7HPAJx8vOB163w/420/UfCWmardX0KSXBELnGAZeQQRjjO0/SgDg/jTMdFvoNXiglkLxiKZ9+CiAgqYwRt4crkndywyMdfNvDPg7xD8Qpf7JjmjtILKBDd3LncrtyY1O3+IAkY7Y56Cl1jxbcePvFd5Hqk09xoenR3d1bQFgMBUJXcVHOSoAznG7GTk59E8HfEPwF8PfBVlpw1F7u+ZBPdraQlyZWAJG44BC8KOeij3oAk0n9nHRYY0/tfWLy7dSeLeNYVPXrncT2712mjfCTwRobxyW+hxTTJj97dM0xJx1wx2/kK881L9pGMLjS/DUz7mxG91Pt3D/dUHn8a429/aB8bXQkEJ0+0DqVHk25JXOeQWJ5H5cdKAPefG1ibOw0m+02xV3s79FMERVFeOYGFlIOFwTIp59O3UfNul+B9cu4JEs79olR5I54POZSFUklfQnA3ehyMGs8eMPEOr67ZPq2t319bpcxu8fnMUKowbOzgdBnoK9c8TeCrLxx4suF07WLhr4IJorgzRtC0LlduMDLYJORnpjvQB4lqjX9jr0k8ksxmuCWZhKS8obruOc885B/Wte30bT72K80xLGW01gkfYobiOV5HHVlygAzjJGVPB69K1vFnmeH9chgn12G5u9NaGeLyLVlhLKPl2sCcZwCQu0cHuAK9NtvH/AID1XS5Pt+mW2m6ikLSPBND5R3EY3JJghSN7YGCckehNAHi2lWGmS2EGo3VpEtrYuUvf3snmSMfu5UAhVzxx1PXFdF4AvtPTxpoGp21lcrNHfRreXUYLRRmfzE2EEE8krhi397vXP6denw74k1DJvDbz+dAyxHMrwlxyWBHXAOeQfoebLa8o1a2vbOwmtILOa3uJkASTJWRSGLt0PzAY7k89KAPsmqOr340vTJr92iWG3HmzNKxAWMcseAeQMnp+XWmadcNLdXsQs5YoUkykzliJieWIyOB0x29Olcf8Y9QFr4EubTz57eS9/cRSLgI7NwY2J4GVLHnA468UAcd8ZrKwvRb3Cxre3EyKywrL5RUEH5z2dRg/NnKbudysANfwZYTNp/grRbmyht57cz6teRRDbjaXSIk5O7LSZ6nO3PFea/E24uY9A8J6LfIkd3b28PmmJdpVvLUFW6AMCeOCOpBHK17h4H06GK9v7y2iiSyhht9NsvKbKiOJSZAOT/y1eQE5OdvXigDsZZ4odnmypHvYIm9gNzHoB6n2rzbxrey6xp+taRdWkSazpl7bT6PtG9ZjI2IGIYYzuEisDwNpPTmu18UzaNa+HL2716GKXT7eMyyJIobOBxtB/i9Mc5rzvSvA/itLqHxdZ6hAupSIfs2k6n5kkNtbkHy4y4IbzFBI3Y43Ec9SAeJeKFt576TVp45bK71CSTZZoweGN0IRwznAwWUjA6Agk4HOJM8sVp58oWEXI+UW6BUC5IZTxk52KRhunX71eoePfB/je40WKK48OGaa2uru4W40y482Py55DI6GMjeSD0PpjPNeW3On3WjTTK9pfRL80bSXMBi+Q/KcqQcd+5+nqAe+fAIO0WrSXE0c1wyxneNzuykv8zOSeTjGB/d5ryDx7EyfFPWEdUJ/tJyY5ZjjBwRlhg4PtyPUmvX/ANn7UZL2x1KBopvLtlRY24MSKzMwjBz94ZyeP4ucYArx34hSLc/FfXTCJAxvmSPe2whwQOS2MDI65HHNAGXHo19ZO119n2RAExO+cSDdsV15HG8DknGSDinadi91OFYbqyshPsV7idCkcb7s4OSQRnGc9uccVli7le02yJEyjcvmn7+SOBnrjr7cmtL+zrVIo2innlDAbY42UiQsNxBbI2YXAPDAFW5oA7jSLO51GS8tLm5sYblroTQwvfFIpGdCpYRj94+5iMhVGSQpIAYDrNN069aUaVYxGyjtZGWWYgHyyWYGRtoUlid6qVAzjEYQDeeCEtwUj0vT7dLdlgKG+u0VTKjN8u1n+6ilgBsGWwxzzgevfDvUZ7h7O2ksppreNmiguzbsjxuUGW3yH5gVU/N97HTgmgD0Xwzp0eleHLKxhW6WOJCFF0QZcEk5bHQ89O3StauK8R+LLTQbY6XowjFyI9yvF5LpDlsEbWlTLEngDueh6HoPD1xPdaRFcT3Uly0nPmSQCE+mNo7cdcnOeuMUAatFFFABRRRQAUUUUAFFFFABRRRQAUUVgX/jLRbC5a18+a6ulZkMNlbyXDBx1U7FIDexx+VAG/RXNSeINbuIJH07wpdlgBsF9cR24Yn6Fjgc54+mc0uPGV7E2W0fSiwyu3fdsvB4Odgz055H160AdJVS/wBV0/SoDPqN9bWkQ/jnlVB0J6k+x/KsJvCFxfZOr+JNXuw334YJRaxMM5xiMBsY4OWOQealsvAXhawlWaPRLWacADz7pTPJx0+eTJ/WgDNn+KvhYTSQafcXesTxkBo9LtJLjGc/xKNvY96ht/GfirWCBpHgW7gjdQy3Gr3K2yrn1QBmP0/lXagW9nBwIoIUHsqgAf0A/SsC58f+Fra4+zDWYLm5IyILINcyHtwsYY9RQBRfTfiBqSH7R4g0nSFb+CxsmuHUf78jAZ4HO3ufQVag8C2TxqdW1LVtWmCqN9zeuigjPISMqvc9QT05p7+LppLeWax8N61OkYzvlgECkc5IDkOeBnhSTkAcmsXUvE/jo28D6T4ZsJGuYzLCrXTSMEHOXGEVSQQAN/Ud+gAOpsPC3h/S3D2Oi6fbyDH7yO3QNkYwd2M54HNaFxc29jbma4ljhhTGXkYIqj6nivlzxB8UvGbF7afxI9vfRyNFNb2duIo4CoIIZyu4tkEYGRxweKwPBGkap8RvG9lpuoXt5eW4PnXbzTs5WJevJOechR/vUAe76JpT/E3Xx4r1oSHw9aSkaNpsqFVlx/y3kB65PQf0HPqVRIkFnbxxII4YYwsaKMKqjgKo/QAVX1bVrPQ9Ln1LUJfKtYADI+CcZIA4HXkigDxX41zXVrr1n5ttFNZny5pNgcsEBZTuyCoXAHK4xuPByDXl15fzaX4A022hdTLe3s80UtuSrAIyqGOD8xJ3AbhuUAYxnlPF3iS68Y+N7mWLzLZLp/LVZZmby4yAMdcEYGcYzzgdABszaZHo0l7p2nwtJc3MJSWa5aSOOzhK/vJSxYBdzFCAc5wnUMAwBxkOn3K25tbB3kmlIivVQYCHd8seTjJJUngnp16025tY3tbeSGznSGWQpG6oW84LnJXPIOTgjkZ+le+RfCU+JRaTw3LaDocDZhsobYrNOfutcOHPyO4UYBBIUjODkG5qfwD0y98toPEerJKMh2uNkoYYxgKAoXjj6cUAeD6bYan4h1C00uxivbu7jLPbxwsQCDyzKTgKmV65HWoPEfg/xD4bui2t6LNYxTPvDABowCegdcjjPT9K+o/h78PLf4f2l6z3wvrm427rjyBFtjUHCgAnjJJ/L0rrbK/0/W9PFxZXEF5aSgqWjYOp45B/qDQB8g+AtEvPFPjSwt3unjtp7kJPOu7O1UclFbqMopUDPAYenHvmm/Cufw9Ol54a12W2y7NLYXsZmtZPmLKNmVK4459siuu1zSZkt7a90eGP7VppkmtrP7kMrspU5AxztZwD2Ld6n0PxPpfiBGFpMY7qM4nsrhfLuIG7h4zyPr0PYmgDzX4g+ANY8WacWl0PT7e4so98cmmz7muAONm1lXBHJAORg4yDSN4s0zTtCsrXXfCmrare29ultJNNpLRy7ct8oJXBA28YbkgnORk+yVxnj7xh4Y0jQ9Q03V9aW1mubZ4hHB+8mAYFchR354zgevFAHgg0+/Hik+IbLT9ctLVSyTTyxyMHZAQwGAjDG0cZbaVOSccXfFegSX8Ft9o02SHUZpvJSUbUKyeekLMVVmLcjaMk8Diu7t/GF/qqqvhb4canf20Ms7pPqM/kKHlJduDkEHceM9CPWo/GFt4lzp/ijxJoujWWk6HcG7FpayPLcSSsflG5VC4aRkyeOQWOehAPQPB+tXerz6uJXimtYb2SK1mgZGQouAOQxOTnOMY4P0Hnvx81RLu00Xw9EJC91eBpCYeFUHb1KkgksMFeoB65FWvgjqmuy6HqljPojwJbs7wzTbkWWUkkpkj164zjPTtXP6x4c1keMH1nxLfwXc+77JbPAweKJABkOTgKxBYHgY5OMElACzrl7eat4y0nUdVljh0jR4ftT3aoEVpIyWC4IwxdQCqKxBG5lJwVr1vwVpjaT4O0y1ljSOcwiWZEXaBI53uMf7zGvlvXtZQ6pqEw2pas0Fs8I3PtG7zHAJ7fKQeWznBLfer6EsvjP4Bu9iLriwkj7s0EiBenBJXHf17GgDY+IHhybxZ4F1TRbaQRz3EamInoXRg6gnsCVAz71xHh34qa1p2gs/i3wrqccdgRa3Oo24EimQYHzKSCCSQCQSMntXXH4m+FpSE02+k1a5P3bbTYHuJD74UcD3OBWdN4d1fxvrEF14gi/s/w7ayia20dsGW5cch7jaSoGeic9ecGgDa0n4g+FdZk8m21i3juQPmtromCVT3BR8Hj2roZ4Le8t2hnijngkHzJIoZWHuDwa8s+N2nRapp+m2WxGmkeR0+XJXaoJY+20EZ7Z6jqPCtB8Ra9oymbS/EWpRzmNXMFsgmRU5JypbAxgduMnpnkA+nb/wCGXhe7EjWlk+k3DsG+0aVKbZwR/u8fmD+deea7+zubySW7sfFF1LeSSGRzqKeb5h7FmBzn3IOa6Lwb4k8eaz4dj1SBtC1uHJiOC9q7OOpDYKkc/wB1enSnWXxz8MnUJdN1qC80i+gmeCdJlEiRupwRvQnPIIzjtQB5NqPwZ8cabYSRx6VaX+X3ZtLkAKMEk7TtJPYc8DIxzmuBuLfWdBeKO+sLmxnSQNFLcxOjp8v8Oe3IPTsPx+y9I8X+HNeAOl61Y3RIzsSYbx9VPI/KtiWKOeMxyxpIh4KuMg/hQB8X6fcSz3sn2VAZVjxarLL5iR9OQDlcjL53EKCwPXGfR/C3iqc6lbXtlb3sliqLFBBcBZDgOAVBAwcszKoQLwNoDc7fY9Y+HPhHXEk+2aFaLI6lTNbp5L8/7SYz+Oa5hvg8mnPcP4f124tllU5hu4xMCc8jeCrrkZUkHcAxwRmgDFGkanql893ax/ZoBvF09s4htlG7kblZd5HRiodRwMkivUPDVnd2djKLy3t4ZJJS6iGfzsqehZtiZPboeACTkmuQt/DGs6UIWudL/tCVI8tc2F+EPmA4DJDIgRCFJCgNhRwoB5r0aGIQQRxKzsEUKC7FmOB3J5J9zQA+iiigAooooAKKKKACiiigAooqjqh1T7LjSVs/tJON12zbFHrhRlvpkfWgC9THeOCJpJGSONcszMcAepJrl4/DviO9ixrHi2dNwO6LSrZLdQcjHzsHfjkcEdaevw98NOxe+sX1OUnJk1Kd7ok4A/5aEgdBwBjigBbv4ieEbO5FsddtJ7gjiG0Y3DnrxiME9jQ3i64uRnSfDOs3oyw3yRLarwwGf3pU85JHHbtW9Z6fZadCsNlZ29tEowqQxKigdMYA9h+VWaAOWiuPHF8FJ0/RdKUlc+dcPdOo3HPyqEB+XH8XU9ag/wCET1++YHVvGuoFCvzQ6dBHaLnHZsM//j1dhUN1cxWdpNdTEiKJC7kDJwBngDr9KAORufBXg7RbaTUdSsnvCCA0t9LLdu7MdoADFsszHoByTWNqvxA/sy9SzsNNXT4bcxy3Bk8td4KbjFjopDHBOeoIH8RXP8QfEi71gtYaFE0RkOIg0Tm73KFYnylO9V+YDdtPQ8YrEt/h3411m/juvMGn27JmWXVWV7h5GHzSCOL5QQScAkep5LEgGh49+JF5Lp1vp1rEbR5Wka98mUuyogx5WQBgsx5PYAg87lrzLxL8SdS1Wdbj+0P3cb+X9mtnaISqN2SGXDBQGI+bk7yfp7Ta/BbR5o0/t7Ur/VNr+Z5G/wAmBW4ztRecYVRyTwO1ddpngrwxo8ZTT9B0+DIALCBSzD3Y5J/E0AfKMmn614l1SbWl8KXB01ItwhjWRIIoFTtKx7DBySc5zjHFe7fA3wwmn+HJvEM9glrd6qwMSqOFtwBsAycgE5b34PpWn8Tje6zDp3grR9n2zVH8y5BYqsdpH98sRyASVUevIrfXwrPPAi3uvakHVVASxl+zRJjoFVecfUmgDG1XWb3U/ivpvhu2RRpthaNqGos54YniMDp0YKe4OenFeb/E/wASXnjrxBa+GdDd5tLWVvNmjhLBnjPzNGw+9tG4cdST1G0129z4dv8Awf4uOs2l3ealHqsCaWsl1KC9m5YFGZzy6k5AzyDtHORji70RaZDJH4df7LZwnfdapGhklnkJO/7Mm0KAGj2mXquSVGOoB1Fyvgzwb4RttDudOikvmMdythEpaWQowZXlyG2cAFt3HUDPSs+fxVZWvi6NfFlml9AroV+z27CKzkwQr7Mnz12lcSkZxghcVzdrpgS31LI1C5ullYSzvD+9mUMqyAyH/WMvBx2UPwM06LW/C1/oUqat9ttLx5USK6S1+7GDuBz2CqrpgjO2LgZ6gH0PPELq1lh810WVCvmRNtZQRjKkdD6GucgtfEugyTMLx9f0/avlwzLHHdoc84cbUcY9QD71kfC7VJ20y60G7kDvp0hFpJggyWp5Q8gHK8qcgdBXf0AZWk+IdN1p5YrWZluof9dazoY5ov8AeRsED0PQ9jVK/wBBNjeSa1oEKxagxDXFuhCR3yj+Fx0D4PD9RwDkcVb1jw/baq8dyjvZ6lCD5F9AAJY8jkcj5lPdTwcDuARWsNdntbuDSvECxwahKzJBPGpEF3jnKZJ2tj+Bjng4yOaANXTdRt9VsIry2L+XJn5XUqyEHBVgeQQQQR7VheM/+ESstN/tPxRbWbJEdsckkQaUt/dQj5sn0H8qzNd8Sjwz4rOnaRZ/2nf6lCZf7MtmVWWcFQJZD/AjKeWPH7scck0/SvDER1uDVvGGo2uoeIWJNpbFx5NoDn5YUPJPHLkZO3tigDn9K07xb4vjxaS3vhLwu2DGjytLf3K4AHLs3lLgcAfkQa7TQvAfhrw7l7HTImuWx5l1cZmmkI5yXbJyTzxge1dJRQAUhAIIIyDwQaiuLqC1iaSaQIqgFj1wM4zx29+1ch4p+JugeF5Y45boXEwlMclvAu9z8uflOQuQSmcngGgDqdSv7fStNnu55YoYoImfdISFAA74BOOnQd/WvE4ZPEvjn4f3+v26Wm+eeUQSmUI8MJlDHjB5QqMAk5HICsAWzdV8X6x8R9Tg0izkj0/SJZClxLdhUcox3FRnqdgDFQcfMOBgGt74r+J7XSNCs/AnhmcLqUjQwLb26IQY2yAp4wrE7T+IPfgA4bx/4bTwz4bj0u7ktmuUha7WQDa87NMiKxxwx2iQjgYBOcnJbylIXlVjEjPsXc+B90ev096978aJbav8Tho15/pVtbRaXZTRljuJadc5Yc5xIc465HcV1r/BnwtoC3erWC3jNDaT4tppFlifdGQQQw9Pfrj0oA9B0COFdA09oUQB7aNiUAG7Kg5465zn8a0qxvCLtJ4L0J3Ys7adblmY5JPlrya2aAPLvi1dfZ/IMdwZphCxWyjYRsBkneW6YLKijdwDkgM2Cvznp862FlahLeL7fHcNcCZipIQHbtAX5jyGJyc4wVAxk+//ABsiZYI5Y4TJJNZTQqI8FiPvMWz9xAB95fmYttyATn5x043V662cMdxM/AVYT0QZLYXuckMDngj8gD6i+EEFzHpN2blhuj8qEQ5yIQFztXgYBDA46juOcn5t8YRCTx94mG5Qy6ldFVbI3fvWGBjv6DH+FfUvwws4rfw00kcbqGlZFL4YlR0IkHEgPXcABkkAcV8ra5IH8V+IJPtCxK11cHcybmbLtwMkkEgnv9TQBkWsBnmOxwojXeSzbcDjOPzrr/DfizxhY3kFnY+Jry0iyGUyy+bCi5wWIbIAyBxjkH86GlrC01tHJdW9yLdQ+y4fyoF+YHaWDDI5J6DJJ59fojwh8OPD0unQ6rc2iRXckaieK2vTLEV2ggFwfmBXa3Bxz6cUAYOg/EfxwLw2t7BpOoOxCxRS77SaQkdjgrjIPb15Fen6Rr97ezrbal4d1HTJyCQz7Jojg44kjY4/4EBXKaL4a0ebWbm3stesLyFysjQxTiSUqCCQRGVCg+pDHpzxmvR0RIo1jjVURQAqqMAAdhQA6iiigAooooAKKKKACiiigAooooAKKKKACiiigArjda8fQwXU+meH7GXWtUiBEvkkLbWpAP8Arpj8qYweM54xxUHxY8X/APCIeBru4gkC391/o1rzyGYcsP8AdGT9cV5L4JvrWTwkNGtdQH2lS1wbVo98gYHLyOWAVBtU4JyFBySGYUAeq2WieL/Edul1q3jKG0tpOVh8PRqFI5H+ucMT+A/pVm+8D2cVi8934t8SW6QoWluX1YoFTqS2RtA45OO1dbZS77OFmkR9yjDoNqvx1UelTsquu1lBB7EZoA4PwNf6ZLevB4b0C5XSyjPcazdAq11KDj7zZaUnklieK72uf8T+J08OR24+ziea4z5amVUHDID1OTw+cAHoayvtfjTxBpsf2GO00TzY13T3MbSSKSDuKocd8Y3fnQB2tMkkSGJ5ZGCoilmY9AB1NYUS6f4O0yW51HVrqbewDTXkxkd2LHaqr65faAo7D0rkPiD4tt9X8PWuiaRdLFJrV0LOWeU+X5EQAeVjnp8h/DP0oAz/AA5ewa7f6t4v1LV7m2/tQeRYWdkpNytnGzbSAoLjcwJJA6555robs+HPJiuNT0DXnjTBNxdRTymMDJ3MdxIA5Oe1aWlXVppemW9l4U8OzzWaKoV1UW8ZXHDbpMF+xyAc9c1dn1XXraMtP4cW4j3kMLO8V2EfrtdVycfwgmgDzrx3f6lBYR+FdMm/tOw1OJLy2v5Jt0lnCrgnLDlhnZsc88kZbGaha1FhFew21nNaWkVlOkHmo4BjMUgXquRwCMcn5TVDw3qOiy+LNTsJo2mmutSkt7W0c/Z/sFpDvbc+eUUbnwhA54qzqtzLdSXsj3Kwyvefa4/tLsZGtQJQp2noxUsV9dpGBtAIAnlzjVNWYlfIS9v9lvI23Lj7pHoCw6859657xJ4M0W8sQ87m3vpwhtpImb/SCJEjkbawG7G4k9OpIGDWnL4t0fTdTjttQeO71KRnmS9d28ouybQcggFSxfjurg9PlFPW/isZNNlFtq07ybGtjDdRqHT5QC+0rk8rkE84bnnIoA6f4cvLbT6XcC8ur2N5jALmU53W80TSLkY4AkRQM4OXx6V7JXyboXimS1WzttLhvGgWe32SySZESIVZ2CjPUwlj06Kcdq981bxfqOp3s+jeCbWC/vIiEudQmkH2W0JGeSMl2/2R07+lAHT6trel6DZPearf29nbp1eZwufYDqTx0HNeW614g8VfEjTJY/DOiPB4bcgNfTiP7TPg8mBHYBSDyGJByAQQeKuaZ4T1Lw/rEuteJtJ/4Sm+mPzahDIJGt0+6AluwGBj+6WPWurtdJ0rUIxrPha7Sxndvmkt1PlyEdUli4GfUYDA56EmgDwOLX/E1pqN9pekaZf6JGsoF7dtE0uoOSrlGmckZyckDj2zivSPBvhzXLo6heWl6lheSMpl1G4ja5mE2MyBUkwFBBAOMdAO2B114jahpsevkW+ja/YF42M0w8okEgxStxujYYIPUbgwweDlRfGPQ7+2QaNp2raxfEfPa2Fo7+W3GcuQFwCcbhn1oA7vTobq30+GG+vBeXKriS4EQj3n12jgVy/iPVPGVmZ00zSYLgYd4ngbcQm3aAwbALb2DADqFI9zUXX/AIh6kzGw8H2OnRZ+RtUv8sRgHJWMHHcdawNT8YfEXw9eqNdtNBjsmbb5liPOk5OFKxPMjMM+nPTjg5AMbWPC3jfXzJqOvwabYRrCiTPdXm2MhCcltrHAYZXuDuOeDXGX1n4LFkk19rN54h1RWMKRacxijUjO0IXXLdRgKOTzyOK7XS/hbP4vgXWz44t9ThuQ2ZfsZnzliw4kkZVYcDG3gce56ux+DOiJGiarqWqaoiYCRPceTGoAI4WPb2OOvagDzHTlv9UCQz3WleG7aOJo7a1iiN1qMyHC/MikyFgqghsDJVeMV1Pg3wHY2051Hw9odxNfQSlBqPiKXyzDIvBKQICx9Rux16jivSJk0DwFox/s/Tbe3Mj+Xb2tsgWS6mbO2Ne5Yn16Dk4Aq74a0qfStMcXkolvrqd7q6ZfuiRzkqvA+UcAZ5wBQB5P4j8MQeHfEuntbeZd6jLd2M97dTKQLqSS9yM44XlSAAOFGOeteu+IoFuvDOqwOWCSWcqkoxU4KHoR0rgPGU0t54us7aFAVbXNLtZM88RrLckrk4GNy5GOn1Fdd4z8R6boegXqXdwv2qa2kW3tU+aWZipACqMk5PGcYHegC14POfBOgE4ydOt+gx/yzWn2nijQ77UBYWmqW01yWZFRGzuZeWAPQkYOQDxg+leG6h4y8Vw6HpyQaZ4j0W30vTUgjPlrAstwqgb5DIpDJgLhRycmtnStVuNVPhzwn4Nk0eeHR7O21Brq9mZd8vKuFCg5+8QeOCxHBFAF741yMNqLLGE+wyNLG+ArAEkZxyehwDxkZAJyyeA2FuAC7WVuE8tdj+aOrNkM4LHAIBXsoyN3v7N4y1LUb7xKbTVns7wWR2xS2bMELOFJUp83KbgN2OdwB54PlnlJaa9qMKzSwwRk/vLZCxljVg4Q44z9wgkY4yQx4oA+ofhvb21r4GsIba5juFUNueO7+0DOem4cZxjheB24r5S8TafLPrevajFZXCWv26dkkMLbCDMRwQMDHTk4r6l+Ftp/Z/gi2sVP7uB2CZQqcE5JwSeMk464HBOQab8N5Ir3QtZJVWjl1u/3IxD8GZjg9QeDQB8jwNDNciV2jjR8rJEjFCE4GRwBnv15xyK19E1LU7KdEXU75I/MGxNPmZpC2Oq7W79CD64wM5H1frvw58I+I3eTUtDtXmc5aaMGKQ/VlIJrhpfgHZWbSSaHr97BlWUQXiLNEwPVWAC/KeMj25zQBifC7UtJjuZDfSXunmZUnE73LBJHjYFjIdgQn1fOCCB1FeoeKvGMugfY2s7Fb9bhPMJzKAq5GDlInGDnuR1HWvJx8PvHvhS8kuotMsPECGYSlopQrbQDxsfCjJ9FYjJ2lc5rrLyM+MF+0zyyf21b2/nvpNzpkKvaqMZ2iSF2f5uRg4bjGKAPQPDmu/29pouGt2hkUlXG19hOSPlZlUsOM9OM4rYrnPCcWow6dDHcQRwQKpGxovLfIwB8oCgZ+Y9PT3NdHQAUUUUAFFFFABRRRQAUUUUAFFFMlmjgjMksiRoOSzsAB+NAD6K5ib4h+FI5Hjh1iG8lQhfKsVa5ck44AjBz17dKYPFmpXyf8Snwnq0x4+a+C2aD/vs7vyWgDxz9pDUHuNf0jS03kWtq9y4HT522g9e2w9u9cL4evrRI9P1O6hspbm0nDO0z+WFRB+7B29dznLAgswU4IFdb8VoPELeNYpdZSwtZL20UQW9pK0wmMch2IWZV53ODjhTtHeuQ0XZoGrPCkEGrajA5kYSfNZHDKAzHI3gfNyTtBIxnuAe+w65dWOpJqsrRzmSMAs+WkdWGdvGVRTtyCpCcE/vCOOi8Y+Jxofh2S5jPlztCZPmDAxDaSCwxkcjGCB0PTBx83ap46vNV8XR6g98zgSiTbaRFIopMbcRDqzYVQGblhkcA4rQ8QeI9XtLS91DW9QN/qE7NDZwTbc2yvne7KvCsUCAAdNxxigDrpfiN4OsWGqatZ6heeI9ORUjWZmC3D+YXJU42ptZiSMDH3RuwKePjL4m1qK3g0XRkkkjkSW7ew/eCOH+4SwKrk4y5xjkYOM15R4e0STU7K/8AEV7FHcwwSbR9oudiNLjd+8J5Ixk9eSNvJIB7TS/h/e6/p7T2tnrU07DextUSys3IAVVTzCpwB5oLBT26bqALlpo91q2o3HiPxX4z0+2vI3lLwuPN+zsoAI2q3yYPy4PJKAYPfb8FWnh658fzz2hvtcttItYooJhEZknupCXkmBJKx4AUYyB1rOk+D+vSLLaw+HrGGxlmMzLJqjGU4+6CwByQCw9CWzx1rq/hClzp0HiKysdEMIi1g2z75l8qMRoqMd4ALtlScAY+YcjNAHojSeIbhVMMGn2eVOfPZpiDjjhdo69efxqAaPrTQn7V4puVYKPmtrSCMAjqcMr+3fp+dYbQ+KrmMnXl1FFVjlNCliSPAyAfmPm9MHAJzk8cDOHfaLo1y0qLFPq9lPuNxpl9LMl+g2hSYjIwZwBg7G5H8JBwKAOa8T+CbbRPGi3U+qTXWk6wLhr6fMUcokjHmNGXXaBvCMOg5De9cxpugaDNcQ2smvNLeQyNG8N8m2Nc/N8+cny8ge5MhHZq77xR4a0Pw7pEGsaVLY3KyXMElnbXNujyySCVBtSXhsYyGD7uC2cYq7NoN5d6j583wp06OJkMU3l3sG5k64UDaOWxknnGR/EaAOWbRPCNzHLhrl7dHYW7ibfJgKNsmMFsAGSc5xjEa/3VrQvPCuiXGpmO0tHurnhIJpm8yRk2kqzKcMFIUAliPuuSMOM6WoeLNP8Ah6iapf8Aw5XSJZv3Qkhntd8h+UlQI2yRwp6Y4HoK58fF2y8VyjStN0+7g1rU447NLm5kiEaNvHLEYODlsgYztUYOeAAtdK0/UtXk05NMlTw3byK91Lpenu4kkUBvKDIu4AkjcevyIueCa7Kbwr4V1OxPiDwhZQRvaM8T/YAbcyheTsKgYkU/dOMHkEEHjZsvD2seDNOhh8PXP9o6dboxbTbvaJXJO5jHKMYYkscOCCTjK9RzF/rs/iHWHufh632AR5Oqaxcr5VmRjlWjYfPKuQd2ARtwSQcUAdZo/iObT4ooteu43sZoTPZ6y+I45Y+WCzcAJKF5PQNgkYwRXDal8RzLqmoap4VntrPS3AjvNT1NSIJJFwA0MY+Z32/Ke2AmR0rR8J+F/Burags13e3mvXsLMUbVZVeOUsWJeOHJCrwSMgcEHkEGs7x5Founa1pttrPh6wj0a0vDcRx28YRzG5QNI2znaG3kqPvfuwRnigC74E8Fp4inv/EHi2K51V3uv9DOoN8jBeGkEA+VASOFOcAfn23iXxhoXgmytzeb907mK3tbOHfJIwxkKo44BHXHauh86MwCZXDRFQwZeQR6jHauB03xHNq2viw0bwjMllKBdnV7238uMyZOJCCAWJUDBB3fMOg5oA4nxt478capYyR6VaHSLObyUhkQbpJlkKnf5hxsA3xqcLwWPzdhgWvwV8R6y7apd6pBvllHmedCxdifmLODxjO1j3+Yg4IxXrWrfETwl4c82CySK8mtEkby7EIRGxOSmc8MxPQZ564rmm1Dxb8Q71BAzaD4djjZru7ZShk3Z/dlX4fG1Q3QDLDNAGLojyfCbULKW21Cx1Wz1ZltLrTrOdQYrks2xwWPTgruOOnOcA1615fiu/ePdNp+lW5GXWNTczjnoGOEHH+y3415h498P6R4f+Fb6X4bkhc2sq3k13I6NKjgD5yR8yu3ygMB/EBkbq9S/wCEr0mx0+yOoahAl5NAji3Vt0rkqpwqDLE/MOAD1FAFrTfD2n6ZcyXaI899JkPeXLeZMV/u7zyF4HA4pda1uHRrUsIZbu7cHyLK3G6WY+gHYerHgd6yzqniHWxGulaadMtH+/eaiNsyjODshwefQsQPUesWpyaN4A0W98R6jPLc3SRFWubmQNNMeoiTPCgkfdUAd8cUAcjqlix8S2sVz4htNA+wI2oaldRSJua6uQY9iNJ0woGODwV9RV/SPh14L1KRtR0jxBqN3e4KyajaawzSuemSyHHUE9AOfTFeU/De7Xxr8VJb3xHp1jqEWrmYbLhVfyWjUSLtB5wAAvuCc969ruvhV4Z+0LeaRDNomoRptiudNlMRXHTKj5WGcZBHOOaAMCTUfEfwv1Oy/t7WZNb8L3tx5Bu50JuLRyBtLEHlSQfXp2PB8h+LOjaboPxTeLSWEUMmy5kjWNikErcsFA68BWwOPmx2wPUvEup3/iDwVq/gnWbJn8V2kKzIUYKk8aEMLpWwABwQV65+Xvx5l8QfE8GuXel3MKvAI7SFPtwVgJiRmfHIL5aTDDnO0nPUUAX9S1+48WeA7G6vHgX+zH+xyyNtZQZkAMrAN87f6zGccnk5Jzwwezj8QJZwTpPbI2wTMMckY/hPzgHGAAQecZHJitdVieJre4mh23F0JJ8xHaUwRgYwQAWJABHB6rT9KWz8qMR+UJgzYLXJVm9Nq44P7s8E9WX1AIB9SfC17YeFGtbVJRFb3DIHlCgyAgENgdAQRgEk/hinfC2FU8Hyzbi0lxqV7LISRkt57r/JR1qp8Ib+XVfCUuoy3kc5uLlmVFILRqoCDzMMfnYLuPf5ufU6PwzIPgmLb0F5ef8ApTJ7n+n0oA6+iiigAprIr43DOCCPY06igAooooAKKKKACiszW7rV7SzV9G0yG/uC+DHNc+Qqr652tn6YrnV0rx5q7N/aevWOjW548nSYPMkxn/nrKOD9F9PxAOzkkSGNpJXVEUZZmOAB7muZ1T4ieFNKd4pdYgnuVOPs1oTPKT6bUye/eqcvww0G/wAHWp9V1huCRfahKyFscnYpCjPXAGOOK6XS9E0rRLcW+l6da2UQGNsEQTP1x1+poAyIvFl1f2zyaZ4Y1mZgBt+1RLaKScn/AJaMG6DqFPUVXN34/vJiIdL0LTYscNc3Uly2cf3UVBj8e1ddRQByY8La7eqo1fxjqDgHJj06GO0VvxAZx2/i65/B8fw78MFg97YNqcgAG/U53uj93b0kJA49B/IV1NFAEFpZWlhD5Nnaw20Wd2yGMIufXAqeiigDxD9omeCO00IPp0dzIpndpGPMceEQ9DxlnQgkEAgV5DpHh59ZuIt7pGiO11JZ7iqRQ43dSP7oJJ5wMZO5sV237QuqyXHjK20iOMN5dpGQV3bsszEqR0OcIR/nGCdMXWnt9M0q1W1ht4VjnujcMvG7LBRxuJOGC/7JLYz8oBcuJfBXhPTbS48P7tVvrqTdNc3kQxZKRIigLg7WBw2Cd3yrzzWEugajqXjCzuL+yt3u9VunuIrJ32Rsu5hs3FhgbxsCdeAB1Fe66R8Ozq17Jfa1bm2t7m0kRreG5B+eRvm3AArwmEHJwFB4OMZnjnwt4V8PeH5EVb651Sx06drV5C0ojABKbzjYqqxyBx82DgnmgDq/Bnh/SZEnnXS44raxuTa2FrIoYQCIBWb0MhcPl+W7Zrua82+C/ig+J/C+oTSJ5c6alO7RgfKolbzAAe4G4j8K9JoAK8f8MX2gWEWvJq2oalBJP4lvEihtnuV3P5nAURgZPGcD8R2r19mCKWY4AGTXhHhePUJJ7eW7tLw6Pqwvb2xmgPnPFcNKsiSAA7wAEHy4JB6k7iAAekzS+GHl+xvdanFNMu4RLNdxuyqeSBkHHPUdQapalbeGvt/9hXPiK/W7kKMlrcSm4YdMMolV8H/a6gnqDVBvEun6jZ6tBdSXOm6+8620cv2SSQ+ZF80bAKh+XcWbaecMc+lWdJ8YWd1Z33iGGw1S8vZQYGiSzIFsIh80fmkBNu/e24nPzDI4AoA5291mwf4e2s9xKl/qnnfaWunCf6NC135h3NjaMquNg5bHTAJHq+paxpmjwGfU9QtbOIfx3EqoOoHc+pFeW+BPCWjHwjr9ldwRS6ipdZLnyS0qCeBJAVBGR/rD0A6V0/gHRdEvfCGlanJo9qb+WALcSTxmSQSL8rjc5ZvvKRjNAHjXx31mLWPFWiTRSCfRxYmWCQBgsrb2DgH1OxR7cV1vwh8Mae6yXGr2h/0uz8nTIrqNVM1tnLvx/ETt5BzgAjg1u/F/Q7LxM+haHDYm61p5Xlt1WUR+Xbpgy7j6EBVA45Oc8Gu0hg0bxRokMUcMkKWzKEjGYZ7KRRgAY5RlHHoR6g8gHK+LdQ8QaJpkHhuO7E02qypZ2GpNKBOgP3y6jqUUE7x1yM881zni7TPD2reABYafrl3p2i6X5UKWttFu+2M+0qSmNzuTuO09xuOOon8RSX+l/EvT11fWI5/7P0G8uILoQiNwSCuWXlS3GMgDPTFYekeI7mDwK2maOZ7pJ50t1KqIvLVl5Az95nUBVCkYBJyg5oA3vhkmjaXdR2sK3RlLERKdpBx98hlG6fa33nwIwSQvQFuv+Jfhq38R+H4ReTtHZWc4uLtVHzSQqCWUEc54B6gcc9BjP+G9jLpluZb+YS3d8d3m7VjQgDiKFR96NBxkYQZyoOSa7y9tLa+tJLe8iWS3bBdH6EA559uKAPIPBN5ceItY13QbrULtdJ1OwjubdHBhaHJI8uBG5EYUYGQCQAcfNmsHTPFXiHWvA/iNZ9ch03SIro2/9pTZDxxqqKIolTqSoGdozlye4rc06X+zLfXPilfyeZFHayW2mQyj5mUy/KxBzsy2AqjoOc8nPjGgabqfia0uZbmy1XUbK0LyKtqoCec4yzO2O4UZ7njkdaAPSPCnj34deDdLlh8N6Tqmo6uXxC13CgkmYngB1ztA+mfrSar4r+IXiDVLSw1FrTRoFuV81bZx5iMCW5GWOQoPBBHBOM4rmALu70H7FeX/AIe8K2JPmeXbf8fMzRFk2uFYsTkk/MQOcjAqOOz8D2u2C91WV5hbqZby2mb5WLZZVUFt3yFRjdjIb1GADXawsbvQG0XQ5hdXuuXlvYvNNy33zI7O3UkeVE2RgYfpnJr6L0vQdJ0YH+ztOtbV2GHeGIKzfU9T07mvEPBur+FNB1ltev8A7PZLFF5ekaTbqZ7tvMRd0sgXJ8xwoHzY4OSBkZZ43+M3iv7Q9jo2mf2QPMMayTASTswI+XbjajAHJU5x3OeKAPXvF3jzQPBVkZtVvF84rmO0iIaaT6Lnp7nivnXxR4n1Tx1qzXmrxTfZIXC2dhFNsiQngHcOZJMkD5R/wIAYqsdlm1xqmsmfUNaOJ5JrpjI0IH3eQeCDsGc8cgdMGvpzat4g1H7XDFcILi5itEuXgDQK8j7AXfpn5sDbnhe3UAHovwf07z/Fln9nRBbaNYSiQ+X8wlmYAAn+8QrN346cEAe+VzXgjwbZeCtCFhbOZriVvNu7lhgzynq2Ow9B29+ta+rxwvpc5uL6WxhRS73MUgjMYHJO48AUAcL8X9Kh1Lw9MbK48jxBFaTvbrGMyXFvtAnix3Uqw/HGK8h8d+HrXUdJ0LxH4asXfTb+1MPKhxbMNw8vAGRtxjcxOK7661bxprA0TVLrw7NLpTWUtvJdWREk7iQKGnWIYI3KPlXnG7J6AVk6Ppmm67qPjLwto+sSWGkXMUNza2MqtDJBLnMirG4yMFMHA6EfWgDxuC4toLuOO1tp3vI5mYM8oyTjsRn5gehHcA+wmjtl2xtcDym3CCaaW4AcyAMAoGRhfuZJOAOaom3SxuSzRDz7VgXgkbGcE5Jz052/L15PFW7XUyYpLeG5khE8Sq7KCGbbtYqxy2Iwdx4Az1boKAPob4K6UdJ0DW78ly8lwQtqjnYqquQBu6klm+Yn5hg9MV1Hwrn+1fDbSbooEa486ZlAwAzzOxx7ZJqj8KJvtPgNrxrsXCyzzEEH5FAO3gHOASC2Dk85PJNXfhQVPwt8PbXZh9m6t67jkfgeKAOyooooAKKgu721sYDPd3EUEQ/jlcKOme/0NTAhgCCCD0IoAWiiigAooooAKKKKACiiigAooooAKKKKACimSSxwxtJK6oijLMxwAPc1zd18QfDFvO9vDqQv7pV3G306NrqT8owcfjigDwX4iaos3xJ8XTNas8kNutrFIsiRso2KpC5B3Nls8ZO0EcdRJ4esdQuNXsLBrO3a9vg8E0CYWK2hRQM45yq5Yn5iCxOVZicYPi7UhqHjnXrmGabTN1y7tuDR3AA2fKw7fdzjK475IAHWaW0Phjwp4WtrG4S8utUP22VGjbf5YPyx8gZjDjLZwG2DsKAPoextYrGwt7WA5hhjVEPH3QOOnFQ6zpkWtaNeabKQqXMTR7jGr7CejbWBBIODyO1XRnAzye+KWgD5y+Fzan4K8f65oGn6Nc6k0wMYLSrCv7lyrPuYfdBYjjOfevZzF4zvJFLXWj6bCT8yRxPcSAbuzEqucd9vrx6codMi0P44WM0dzDHb3GlXM0qFypU713E5ONpOCB6hia6m5+InhO2vVshrUFzdMQBDZBrl+uOkYagCh4k8OXS+HNXvLvxBrd5JHaTOkEEogTIRiAFiCs3JPBJzwOcCoXmKav8AD3+xVFxpDpNAbiM7lVBb5QZBxzsPP+yfpWofE+q38a/2X4S1GRHjLCW/eO2TtgYJL8g/3R/PHE3vgXxZoci6r4f/ALOSKO9S/bRYWkKRuqkP5Ttj74ZlK7VHQjHQAHf+GYjDdeIVOcnVXbnH8UUR7E+v/wCrpXKeFLtLr4LarciVpA41NzzuIzLMecZ55z+NbHgjWLTUL3UzaZNvf+Vq1s5YEtHKgVlOOhWSJwR2yK5XwAlpaWXjjwXcTxW3l6jNFDmUDKToQgXOPmwhP+GKAH3VnrWpvZar4S0S5jke1hhvP7TfyILqNACh2giTepwQ4C8DBBHFdD4f8MeJ4Y9RbUNai05b66e5+z6ZGHMTMctiSVTnJAONnc+uR0PhS9TUfCOj3ke3bLZxNhW3AfKMjPt0rYoA8qSBNB8aalFFd3Ooa3H9nuLNtRn3NcxlGV7dZMBUY5ZgmOuDjHSG305llsvG19PrFtcXsTDUJ7IjdaSK+ArxYIMaAMvIYgjJBySOusrK11Txd4st7uFLi3K2kTxSKCuRGzZ65zh19MY4rB8E6NY6vaatPY399pzw6veQMlldMPlEnG5Xzg4APIB59OKAOK1pde1PxToup6hfJ9j1+xu9OsJkgAKROpMbPg4y4O7A6D15Fc74asru6vPtlxJaKQY4FbBaG4QZ5aNGDDAzk5AAO1c7gK7LxJ4XZfg1FqUdzqV9c6eYpbW2uJFdImSULnaAM/JuGMkcnA6Y5LUtQg8K6mus3EUjm8kkt7t0IRZ5VLPNwAeVaRF54BUkKu1QAD2Hw/rGn6XFJcX37oTSBo5Z5VJWM7U3HB2JyACoCj7qjcRXQ+Jb8w+E726t3RCYcqZoxgg4yNrFexPU/n0r5UTxRqGs69b2tkkcFjBKsiLtY+TtIzL8hLA4AHy9FGB6n10eOE8P2l3GgkdomMdjZtC525JB3oSzsxdWxkgLuI+oBz/xbvLG10Dw74G0XYjXBS7uHGF3A5Cs/uxLOQemBXLXaeCrHwpBY3P9qahqcJcRK17iJcYYmNRwIyxkGTz8pbnIFR6LdR+JfFWpa/4v0zU9Vtbmze58+0ZVkgijdUMhClRhQNp46HOK2YYvgleXEWweIDI3yiABmLHoOmT+RoA5GLVfDel2S3C6RZ3l9Mm/yZA5iiJXb0bnrlsE46H2rJvn0OMBooTLO4LSKrkRoTxhcd+/oD2IGD7BJqnwX0q8No/hfUJLxThoJraUyKcdCrsPwH8quyeOND0bQ7LVtH+F0cemXLbIry4jhiX03MVVyBk9T1wfwAPIraPVLq4ebTdCuV6rHDZWzv2HAdRkjjLHJJzjAGTXX+GPg9401Oc3d5ZwaaHJKveyElckEkRjLAnnup/r6nbeJ/Euq2rXX/CT+CNKs8A74ZjdMpPXLF1Uc8fnXP68PDkug30mpePtY1y+S2mEJikdbXzthI4gXbnOOCx9KAK2r6R4D8Fxm68T65Jr2oR4Y6XAyiJ2BO3dEucAE4+ZsYAGD39B0rwzd63d6Zq3iC3isoNPIk03RrVh5VswyFeQjh3AIxjCr2z1r5ctdCng0C/u7yOOMBF2LKcMhJBzjrkrkAHH3sjvj64tvHXhKdYVj8T6QzSKNoN4gJ69ic9j1oA6KuO+KVjfah8O9Vj09mMqRiV4lTcZ41OWj/EA9K6e01Owvxmzvba4HrDKr/yPsamnuIbaIyzzRxRjq8jBQPxNAHI+GPid4U8SWcXk6rbWt3sHmWlywidG7qA2A2D6Z7Vt614W0HxGgXWNJtLwgYVpYwWX6N1H4GuD16LwzqWo31joGn6P4g1rVmEjRskbw2gC4aaR1BxyORncxPHqLem/DjU/DWm28mjeKtVhnt4MvZjE9tI+MkJE5AUE5AGR1HPFAGLr/wCz7o11vl8PahPpcpJbypR58XUEAZ+ZeQOcmvNdU+CXjjTZAy2FrqkEbEAWsyrlcE/dbbjPtz6etegf8Lv1Lw7qz6X4t0KESR/fmsZgCAGIPyMTk9PlDfoa9B0P4leD/EEamx120WRv+WNw/kyZ9NrYz+GaAON+FGqrpvg+90zVbkWGpNNI8FrfKLeTb5a4KxsMAZB4AIA7dc6vw58QaVoXwu0OLUbxIZY7fc8YBd0DMxBKqCRxXe3+m6fq9obfULO2vLdufLnjWRT+BritR+EXh+5ER06W7014X3xJHJ5sCnJP+pk3J/ER044oAsXHxL09rhI7CHzYTndczSbEA6cKoZyeRxtHUd63F8Y+H5BF5eq28jynCRxtvc/8BXJHT0rgrvwB4mtJLdIpNM1e2jUR+dLEEuUUdNqy+ZCvccIO3ByRWVf6lPpSrDrsWr2RbA8qeOSddmcKQ0bx264LEkkDHy8Y6AHU6tBPZ+JXv5LDTY7h/mjLRXOpXDLkcrGMLHnAHBx78V1ugNfT2xuLye9LZKCK5t44TwfvYXJ/M+vFZHh/VBrN5aCcM5hRnjk/tCLL9BkwwuV4zjnOK1L/AMXaHp9ybaW+Etwr7Hhtkad4z6MqAlenfrQBt0VBZ3cd9ax3MQkCSDIEsbRsPqrAEfiKnoAKKKQkKCSQAOSTQAtFYl54v8PWLKk2r2pkY4EUL+a54z91Mnp7VWPiue5dV0vw7q94rY/fSRC2jHIBz5pVuMnop6enIAOkorlWTxxqBVvO0bRozklVV7yTtjk7FB69j1/Glh8HSzRgax4j1jUWJJkQTC3if22RBSBjtk+9AHQ3moWWnQGe9u4LaIYzJPIEUfiT7Guek+IGiSSmHS/teszBipTTLdpgCODl+EH4t3HqKu2Xg7w7p5LW+jWm88mSWPzHPGOWbJP51sM0VvCXZkiiQZJJCqBQBgDWPEN6gNj4bNsHPyvqV0se0YzkpHvPXjGR+FRS6P4p1JWF54ji06Nhjy9LtRuX/tpLuz9Qo6VLfePPC2nz/Z5dbtJLkgkQW7edIcf7KZP+T6VEfFl9eEDR/C+q3SsSFmuQtpFjnk+Yd45H9zPNACw+A9F83ztRF1rE2Qd+qXDXAH0Q/IOp4C9ziuhtrW3s4hFa28UEajASJAoA+grl3tfHuoTnfqOjaPbYOBbwPdS557vtUdux6e+KlHgiC6ETazq+r6pIg5El00MZb12RbRn/ABNAHg+tPaT+NvEqXtuht7TVZJn82P5d7OoUMytukYqJAqDkfMR6r0t/tv8AxZZas893Ppmn28ECSoAJVkdy7qFJCKwI2gLlUAHOUxXL6hpU9r8TNY0mG1kHh6xvRK9usghAL7WUByOpxkZ4ChiSFDGun8aQaLbeKLRdNeJop7VHdSWWSGNmyxYtkhpF2gE42IHwMkUAe4afqFtdp5cLKHRQTGHDFVP3ScE4BAyM9RS6lqlppFhPe3koSCCNpZW6lUUEk46ngHpXgth4nvrXULieXUZDYWVxud5QQJpV2/M3QnkKqqeQMDGemVrdx4i+JdzYabpEF1qUIXzJ7plCRhCx+UvtCjkc4z0x8xU0Aeg6Rpem/EXxRHfeI9NiuTBpEMqxykcGWWRl4Q9NiDhvU8cmvT7HS9P0yMR2Fja2iABdtvCsYx6YAriPhH4fn0bQ9Turt1kub2/k+dM7SkZ8tdpPJT5TtJxkEe1ehUAFFFFAHkeraBe+CfGJ1+yW1stCmux9pvFK7reOcqrqytxtEqo4PRd79BXP2NrrviDxHqus6Lo1nqg1CO2tbm9e4WKKOVAshbHLEFRHkLyDkcEce73Nrb3ls9vdQRTwSDDxSoGVh6EHg0yysbTTbSO0sbWG2toxhIoUCKo9gKAKPhjSptD8MadplzKk09tAqSyRghXf+IgH3z/gOla1FFAHEajB4g8OeLL7VdD0FNYsdUSE3USXaQyxSoCpcB/lYFNgxkHIrlrbxprdtev4ztvC91F4VvbZJr9pLuEkY+UTRqGznbwykchR0PX12b/UvwD8p64/rXlt5KJf2a2YJsC6MqBck42gL3+lAHM+NfEEaeFB4f02+t5NP1y8F5pt7llSKDeZZUYAE7kkUDaBkhwMZGK4jxPYyXNxo+nXEDzIfMIvFRI4pmBCklxngDYWCsyr91eSTXVfEODSf+Frx21nplussFl9ougdkQkmYg7st8inaAS5U+4zgjkdYlv9L8W2V7Z26RzTuqCJndmb7rghDgKFyu1Sdw+Unkg0Ae9+E9L0bwtoy6fYWcEmoW0Uu5oUGZZRhnCuRuY5xwM4CjIGBnznQvDvifVfDWv+M9UuJLLUNWhMaTsCHgty2XbAIIXaoAAGT178+j+K78eHvAwu9Mgjs7ucLFEZWIMIcAMy9drYAPufVsA3/BlpazeD4baRvP8ANi23Mch37TjbswcgAAfd59cnOSAeGQ2Q0TwnoEpBVtS0bV7KZDx5bFTLGGx65U4OSO59KXg2ysbG10WaOWUXlzrVg4AiACr5owXkzkAg/dHGcH2rtPi/octt4Kkhs5I4ItImjuIrWIEtFbuPKJZ+7M5LHOSQfYk17DTEtNF8PX13PbRXN3qem/ZrRFCmOMSryW4ycL24wcA0AW9U8ADxV8adYup2drfzY0kAXKxotvEcvkYOcgKOehJyBz6R8OURPBUNuqgJDdXcITbgKFuJFwB2HHQiovCvHjfxxx/y+23/AKSx1l+EPFmg6L4Whs5L9ZrxZrqRrS2Uyyr+/cnKrkr15LY60Adcvhbw8l414uhaYtywwZRaR7iPrjNQeNJPsngLxBLEgHl6bcMABj/lm3tWKnxDW9ZF07T1dpG2p5s4IycgbjEJFTnbncQecYzgHF8e67qF14W1awkv7KzddPuFuLZLWWWa4cKw/dg4IizwXK4zznHJAJH8HaVoPwhvoLSJfOvLBUknlP8AfxgZwcKN3bnjOc81313omk6nC0d9ptldIy7GEsCsCAenIPeua8Wo3/CpLmIAM5sIkVQQ25jtAA5Gcn359af4U025020a61U3lhDCm9YZp4Y4VByWOyIbVx/tM3XqcUANuPhL4FuNhPh+CJkbcrW8kkLZ+qMDWTrvwu8DaV4f1HUZNKkkFpayzDzryaQAhCc4Z8Z4/WtTUPi14K08sq6yl5Io3FLGNpzj1yoIx+Ncn4m+LGn614T12yh0q/ihudMmW3nlAxIxQqRhN2Mck5OMDkjNAHLeBfjO3hPTrPR/E2gywQLCnk3VvAI3dMfKShADDGPmB9+a7+b41eBL/RbvGpukrQMPs81s+5iQRjsD/wB9j6jrXT+HrHTdd8CaF9vsLW8hfT4CEuIllXBRfUEdh+Vc74s+HXgW00S8v28OWSS7cJ5aSqNxPGFiIPU9sD3A5AB4L4t1TRdV0rzIryyNwshEMUUD78LkZLYCoh/hRRgYGc5LVykV1ZRxRloI5MDc0ZGGZvmUDdjpjaTxz7duz8XeEtMs9OF1Yrb2tnbQF3nM5lmu5WOFAVSVVc4xjjGfmcg1wkPl/ZX+TLgjLnbgcgjAPXgHjvn25APSvBt34017ULWPwRBc6NaQxpFcz/aHlt8gs29xJlc9gqjHboa9A8PfE7xrFZ2c2saJaX9vcRecJI5ltJ9nOD5bn5+Bn5B/TOt8Mdc01vANtpljZTWsb2VxPE8kyuZCjbZdxUjaVLpjJHBHIrzvw7p11f6VZJb6gZ82kCbEgJdDtyU2xs5IAOMtH6noDgA9e0z4s+GbxEXUJLrRrkqC8Oo27RbM4x85G3HIwc9x612tvcQXcCT200c0LjKyRsGVh7Eda8LuLCykaZL+S6ucsS8MTbdhHJDrEZTjhsjy06DpyBpaVHo321ls9O1GzvpZA0t7pNzKCCX2nKBnDHqTvUADHsaAPQbzwB4bupTPBp4067K7PtOmubWULnJG6PGQcnOev5Vk6h4AvpZzNBrr3wJ3eRrKtPHuHQgRug/MN+NV9F1rxRHcfZxqOm6ryVWz1ErZ3xwOeIy6nHPVV+6e3NazfEDT9PnW38Q2N/ocpGd95EGg6gD98hZOp7ke+OKAMGHTdc8P28MmpPeRRPcBIbHw1bowY8nMv7oYHqSccc16Bpl+2o2YuHsbuzJJHlXSqrj3wCR+tPsr+z1K2FzY3UNzAekkMgdfzFWaACqep6XZazZtZ6hAJ7diC0bEgNj1weauVnazHrE1msei3FnbXDSAPNdRNKETByVUEZbOMZIFAEtlpWnabGI7CwtbVFGAsEKoAPoB706/1Gx0u2a51C8t7SBeTJPIEUfia5t/CGr6gCNY8ZarLGf+WVgiWa9+6gvjB/vVLYfDrwtYXQuzpa3l2CD9ov5GuZM8cgyE4PGeMUAQp8S/DV1J5Wlz3WrTZA2afaSTDJxgFgu0de5FKviPxRqIxp3g+W2BP+t1W7jiAGOflj3tnPQcZHcV1ccSQxrHEioijCqowAPYU+gDjDoXjXVI9uqeKbfT1yDs0a02t7jzJSxx/wABHQe4p0fwy8PSMz6qb/W5CoXdql28+MegyAPy7V2NFAFDTdE0nRozHpmmWdkhO4rbQLGCfXgCr9FFABRRRQB5rZ+EbHWfiL4tvbmW9huYbm28qa1uniO02yAggHHr26HHTIraf4a+H7q9e71L7ZqUrx+WxvLgvlcg47Z4GPcdat+H48eLfFkytuV7q3X7p4It48jPQ9RXS0Ac9ZeBvC+n3ENxb6HZCeHHlSPHvZMdNpbJH4Uzxlf3NhoAs9LVRqWpSixs+OEd85cj0RQ7n/droJ54bWCSe4lSGGNSzySMFVQOpJPAFchoMyeLvFE3iaOVZtIsVa10l0JxKzAefKR35AQf7reoNAHT6Tplvo2j2emWoPkWsKwpnqQoxk+pPUn1NXKKKACiiigAooooAKKKjczCWLy1QxknzCTggY4I9ecfnQAspxC5zj5TyDjFeVtg/s17WAAGkhcYxwDjnp/SvVJf9S/zbflPI7V5hfGVf2bf3g2SLokfQAYwox0J/wA+nSgDzfxX5X/Ce+L7u5tXuv8ASo4FFuSk4VUXCq2MKuBzjLfLnhQc4+tWltrOqaVqN0L6zsI5ljuZPIctD0wAgOV3MCFJ5Jzl3YNt63WYPs/xP8XC3mljLyQl3ABDI8cchHQ4A2liVwcDkqBmq2vwaXL4t0LSpN1paXF6LpmZTtnBZEUqxIUgBTwoEagEgtmgD1n4i2v23wza6VHcfZZLm4REuJXbMQUFmIfBAfaCATnk5HIyL/g2wTT9PeG3jZbNTiHfIx24GGVQwyACNvPUqT3rI8b6pb2fiHS0vYne0jhlLKkoUu0gKKACQM/KRnr83GOa6DT7y4eW0sSVE0cZa5aUDcOFPlqMjJG9MsBt6cZYYAM/4m2Yuvhp4jRUXd9ieQnpnYN3b/drx65vY7X4X2eo2m5tblurWaAx2zPIuxh8w7bdyDHOCVAJJyB7P8RphB8N/EbEAg6dMnP+0pHofX/9XWvP9S8MM3gqPS4bm5gu5tXs7UyT4lkRkA5Kr94AEkA9VC8AUAaPwUur68XxNcalNNNePeRGR5yC5/dLjOCccYGO3TjpXD6Zp41PVb54NIa/1Fr25kP2K2UquJ3O2WaQyKAWHACKD13HBNep/Dbw6vhtvEdkbtryZdRUPOyKm79xEw+VTgY3Ef5wPKD8WtU0fTJNE0ZrO0mtbudS7wmZ5cyuScDAXG5TyDn1yCCAdpYeAPE+uTQTa1JbadbxuswRibicuvTLbjxg8/N/wHGANbW/AWj6D4L8Q3cT3rT/ANnTkmGcwjPlnOETCnP+1uPQc15e/jbxvdtbvPrWpRH7riGAKWPzY+XYAoJ4wct8uPStmy1nXU03U9Nm1q6lWe2me7Fy3nTAeU+AoydowEGVBHJOeCaAPRvG9zcWXwmluoY4ZJYYLWRkOArAPGWAI4HGcYB7YFeeap/avjiHUPtMcs9vLJuAjbzoYFU8bc5XIG7ljEOOvBz2vxJLt8F2MMSlylltj2FxzLFxjDEjtjnPTnoeGma51JBPdzvMiFfkdTKID8wJjRAQuCRwRCfujvyAZGr2VhZJb6tK6SzW8wjLWhEjKS+AoZf3fphTI5wD8v8AdujSZ2822gjSWeS3eMxqC0u7DfKw4KDJbgx7TjIJqW+tbG9to7bAld42/eq6ySEcMDhWK7d2BzKeVJxwAWSK0Ulyi2cbiCQpJC8C7Yeh7r+76jnyoxnHzZoA9U+E+rLq/wAMtEkACvbwC0kTdkqYvk55OCQoOD6+mK1PG72cfhC/N+sxtigV/KZFPJAGS/y4zjOQfoa8UsL/AFPQNYuNR0rVVhvblMm1WMzRXWBlSy79vTo6OSApAU5xXRy/F69vdNlstV0C+06WTKC5027hkZcAEkBypByRxkEZ6g0AcP8AE24VNLtYZp1hlmyhtn3sBnB81xgPvwq/M43HPCKME+Z7rB0WJdwjVQ0kxiG9m2jKg5xjIJHAJyc12utyWOr29zaafJfPaNeNM6w2RQBiGG6TJG5yx4yVAUYyTkVjWfw91e4MYuZYYAygqC2/OfQj5fU9enrQB6r4V1Pwx4b+EL6layebqt1FNY2y7CHMrgEoAThsZUswwOMdgKmtWS5gsdCsY9Y1KMRJAyxyRRxNiIfOGPyjBdh8qMfkPJzzz8Vv4a8OWENvfRa7q2oRwmRbiOzjaOyXnCjLZUAhz8pGTuI6g1r2h8mxt7yTUUslmA2z28crSFei7pC0aocEZPmNjPNAG1facmh3kVpfx2MJKAxxq6Oflxj5pmYlhjrHB375pbmznWzEOpTXU1qx3xQAeWSAvY3BQH7nRYu/eqmnJZabf/bzYX0cQYNPctcratINpHDhY16sePNJG1uvfXe+dbaObRNL06xiL58y2ee4uJcrnGYY8SfeJ2+ZzgZKgGgC7YeF5pQYLW2t4LaNlt/MkWaRsABjlQYkK5AAK5A446mpdRm17w1I+nWVtPq7XMSnMySSxjAbISNFCxr22tIAflHcms2bxBerHHBPql+JE5WLz4LMhRjrGvmzkYOeee+KzLw3r26z3lhd2wRiTdXd3NEZMcFDJPNEcFN3AQg56CgBl3pdzpt+99frp3h+5mRmEsV4mnFs85KQtIznIJIPU969N8JW+rxaaJNT1kakksaGE+UFKdc5bCl8/LyVB69a4K3F7c6iLbw7pC26z4Bk06QQwxRjHMl15JYuR/ChxgAgnNdR4BZWm1IHV7LUZ0SFJfs1/NdmMjf955GI5ycBQvfPagDtaKKKACiiigAooooAKKKKACiiigAooqK4uIrS2luZ3CQxIZHc9FUDJP5UAfP1v4v8Tr4t8aS6RfNHH/aLRJFKgdQygxg8qx6KvAKgDk8V6boVp4u1zw7ZX134pFpLcRiQpa6fFgA9OW3dselfPdrJeXmlTXhNvbS6tqBeCaSMNIZHkBBB4IwRnPzdSe1fWtjaR2Gn21nCMRW8SxIMAcKABwPpQBxHijR49I0f7RNd32t6pcXCW1guoyK8aTyvhX8tAqfLkt04C9RXY6PpkejaNZ6bExdLaFYt5GC5A5Y+5OT+Nc/qpXUfiXoOn7mC6daT6k4B4LNiGPP4PKfwrrqACiiigAoormNf+IXhbw088WpavAtzAMyW0Z8yVeARlVyRnI646igDp6K8Zv8A4/WzTSJpOhyMkTKXkv5xEdpK8hEDsc5J9gM47VzOq/GLx7fW11DZaRaWqbd4lTd5iR9d2GbIyO5A/CgD6HnuYLaPfcTRxJ/ekYKP1rjLr4seFYdVOmW13JeXIZlYwRkxLtGT+8OFI4PQnkV4baS23iSeK6vob3WNSnXEltGDePu39QwyqDHUArwOldhpvg7xvqLlrTR49I6AXmo3ILlQRuXam58MBggt0zz0oA0bf433upToy6DHY6aJAJ57h5JZBEWA3BETqRkAZOT7VqXkzT/s1GR9uf7FUDb6AADuecAZ565q5pHwvk07UbfWbnWU/tCJtz/ZrREjdOSyHOSc5+/kNjjPpla5qkw/Zlju0jV3fTLeEgqcAFkQnGT0Hrx/KgDM8eaTat8SpY7yZo7TVtLilknQ4aLyn2sVJyG+Q5xz9CcGsbRNI/4Tf4h6TMLhYbO0jeV4kJLsQ2SGfG4ljyS2OuQBnaNXxrrvhT4h+KvDGlaNq839pLLNCby1R1MW6M4+Zhh13AZAJ4zg882vD2m+JPCGrFtR8L3+o3hYifUtMkjY3KnPzMWweOyYX1YsTmgDU8f3MZ8f2sTCSWaLS5PIhS52KC74Z2HbAUDj7wyDn5Q3QXuuroun28MjtNchUFx9qfOF2biDKQBwSrE/7XGABjj9bt/FHinxja6jpHhu+00NHEk9xqZjhwisSFBUsRy5PALHPbArqtM+G4kuEu/E+ptq0qnd9mWPyrYE9cpzvG75sHgHtQByHxR8bX2sfDjU5dMtRBpDzC1a9lP/AB9HzMYhHB24VssR2wAfvDrPiDqMXhXwtaa9Kj3TW+pW9zKocgMSNrbATheCcD16+tcR8ctStr6+tvDUMsca6fYy3rxiQKpcrsjQLjO4LuIA/vCuk+OkYT4XJbIYoVa7t4hv4VRz6ZxjH5A0AX/hd4gsfFl34p1+x86NLu+iHkTL8yBII1BJBI5IPA6YryO1s0bV9UunWKBI72aMSs4AWPzXyAOcZx1ZiDnvXqPwPRU8NasqyxSgakQJIoPKVgIYuQuF499ozXl+k3Om/btRlulMswvbhPKB80pH5pPyqW+UAEnnBPrxQBPFLcXqSyxLIgikDvMyMyxqASE3t94/dbuODxkc09SkuH03UobeGWWUQMAkDnNuuwHDNyeBnIOBwcdOOj1C7n1e3Rnu3tLfOWlkWMs03BZkbiMHAAO0SN3OOSMXX9D0m38PXrWts11ePb7Ptl0N7bmkHOZDuXAJ5EUf8WDxyAetfFWLZ8JbqFzHHg2iH92do/fRgjaATjrx+HNeetbYnt4JFkuY7RBndGsXlY4B27gYxn+80X0Ga9E+Ll3NZ/Dl5rZtkou7QoUAyCJkYbeeDkDpn8ua8iW81M3jbZLezLIxeSZjI5Xj7uz5ypGfulU4yeKANy2mhsrYI1lE7XRdI4SxhMjMuQFSMZkzlSCyspOBvxg1jM097c+TZ2kotE3GyWSPc8QHJkPlk4UgOQVGzOPWrGknT473ebl7kxKx37PkiTOWYKpCZO7oGbkDOAMVRubkxahJp2mE3NpZSfJM+BDhWGJFRMjbgcFQucdT1IAurIZNPkh/tC3tBboMoigkyHOcBCUBJDfeYEc8ZBq1HpNrIsW6G2uLlmV3kvT5zkDceYtpCEnaMtGBye2SaEcMrRzC+G2Joh5uZNgIzw5K8se2fmHPOa19N1E39va6lbCWeCCNlNy4I+YE/ecHCDcTghohjnAycAFe6tjbxvqcEF5GYUSK6ufIU714XbHyUVs4+6QcHpzithrWK2G24toLaS4QMz6nIWmZARgCLAZzgHGYSDnqcGlHyabJE8NpDHqBAM6KIHQAnBE77dx+YdHkPUetZNvMtls0RLZZntI0mRmikmSRGIAZdybOpHztGM/3zxQBtpB9vvIdPt0lv9iA+UI0WFCeWfZtby+ucMIyeCMYBqxbK9tqP2m5nSLzcLF9nkNzcP8AMp+WSPzJCMDHMqDkDiqJigvXhl1K/t5fLIxEs5m8soeo8slFwD080Zz0HBqxpWnnUb1rW1tVVYY1Ml3dsyIBgnHmRhuCctxNztGfUgEdt+/1KWPSrB5HKE5gVTLHggbTIDIw5I5aVAMHOMYLNUtxJHILjUbGyeWPY+2dprqQMxJDeWZpBnIyA655564gvGWTXTpY1m71WC1QW6xTMJIfMVeWVGEpyTuAxERwADzmtUhrC2tJLyJYZEcoLmcxgBjyVBnb+6QcCAkFuhNAFHT9ah0ZYtHbV5LcxHYq3Mg0uIqAMkpBvmZuDy7L6k5xnds7SSUifQLC+WPaoke10tLYuODk3F3mRsHBBAzxn0NR6c9hfSzR3PnanPbAp5BN867iMcBIkjCdOQh/hHGRiRPCuoJp1jLZ6NPeTqm1HvI/NeAKRhQLmUbMAcEIR0+tAEzXAU4vrrT57zmSK0Opz6jKzD7qlQ0aA8t7HI/u5r0DQ76+unuYrzShp/l7WVTPG7tuLdVQkLgAdznn05w9O0Xxa9siSanaaRGuSEtoI55DkDqxREHIzgKevWuk0zSYdNM0u9p7u4IM91KqiSXGcbioAwMkAdhxQBoUUUUAFFFFABRRRQAUUUUAFFFFABXHfFDWJNI8AakbaQre3Si0ttpAJeQ7ep4GASc9sV2NeDePfFEHifxtFBbXMbaNoDF55CGKPcYOTwrDCAEBjt5J5xzQBW8E6HDfeIdH06BnIsQksuMbRtKuSdoHXaq5JbO8HJr6Crzv4T6b5mmXniS4QC61ST5CCdohUYULkk7eoHJyAOeleiUAcJ4UZtT+JHjLVWJMdu0GmQg9vLXe/PT7z9O34102q+JtC0ME6pq9jZkcbZp1Vs4zjGc9K8B0u51KebXJJNaNjZ3uqXUptklaLzXZwhIIO9+mNo3jk/LwawL/AE77fcW7aZpk+p3U+ZBc264LjdzlcbiASeDGpOM9iKAPZNU+N+g27tHpOn6lqz5AVoYvLRicYwWwSOeoUjp6ivPvEfx48Xqu6y0iz0y3diY5HPnsRjpuyFJ5B6en42vDXw08VuIJ7vQYYowMfZ9Q1RgiruzwsalgcHu3XPHr2yfB2G+1S31HWdZuXMJylrZAxRoMg7QzFnPQAnIJ9qAOC0XxR4w1Ke2trnU7uSeeQS28MkgzKVAZhmMBAp5OGyAMcck1LZfC2+1aIT3GgyO0oBnlnISSRiUJ++2QMA8qRjkYHQ+96bplppNjFZ2aMsMQwu92dvfLMSSfqauUAeI+GvgXfadcTC/12NLJ3yIYIt8jIDwCzDaDjjIUkdiK7a5+FXgp0jmv9PMy28QTfcXUm3A7sN2M9s+n0ruK+V/i54t8T6n4n1LRtTmm0zSbecxw2oBUToCdrkD74OAfQZFAHt2pfEHwh4U02OLTQl4qLtjtNHjWTaqkj+H5VAw3U9q4+++PkkkPlaT4UvjdlC2bo4ROp/h5IwPUY/CvG7RIvIij0+DULp0YPuiItIhyArZIJJ3HGdw4Harttfat9tKt/Z6fZla4iimklYlzjByW3OSV24zjk8HFAHq2k/GHxJqCxm50K3t0wys6nl5Dnaq7mwOOuSc47bhh+rWcs/7LaQqgLx2MLsCRwElVjz9Afr071xbtZ2MdjLcQmbU7jabgQXEaSKzZJDON2zGSpICHAORxk+g+RGn7M8qQpGinSmbCkAHkknPf+ZoA838It5fiPwr9ijT7KmpQh5W++CQUxjHyqc4AJLcD1r6jr5StbuLQdN0/XhG7ywX0N40ckrbpWG5skbSVLDPPAOSeBiveNK+JNhqmlR36afcKjpvKi4tmYcZxjzc59sdx60AdrTJpo7eCSeZ1jijUu7scBVAySfauP0jx3N4q06W78MaHPcpHIYWkvZkt0DjGQCN5IGeSBj0zzjnPHOjeI/EZ0/w9d6yIbrVd4+z2COLe3hQBpJJDkNJ1RADtXL9M0AeTXF9deNvEPiPW4pzLFKzSxwxQIZVhVhGu84yqhADjIycn1z7B8cWSPwDZKxVN2p26hnz8v3jn5fYHp+HajSvgnpFhA4l1jU5JpU2SG3KW0TDcGI2Io4JHQk+2Otd1r/h3S/E9gljq9t9otkmWYJvZfmXpypB70AcX8GJI5/DmqzwBhA+onYWC84giU9OvIPOAfWvJtOlt7CXV3ghhguJLuVpriRQzsC7qApY4UdBnCn/bGRXt/wAP9OtNKm8T2NjZLZ2kOrlYoVBwB5EJyM+pJPHHP58f4W+Gem69on9qHU9Z06+a8vFkNrcKMEXDj5QykofkX7uD1zmgDlZPM+3OkkZaXasjyTjzJD2A8shs8kHeyvlW4Yg1n6rd2a6K9zex3U2JomwVBWRd65XDbl5AbhWX0I7V6APgtd2IMWneJjLZlhIbe/tBIXYHOPMVlKg8ZKgN155rkPE/gvxtotnd6lPp1nfJayRypNZyMTsjYNkofmxhTnJY/hzQB6n8XLkQfDDU7gYGGt2BIDAHzo8E9QQDg/hXiGnw2eQ17dmecu0s5ePcoLEj5QvGOf8AbHJzwK9r+L8iL8LtQmkUMqyWrEcAf6+P68f5zXj5DrsRCsVvK4kDs4UO5x8iquWLZY5Zdv3cYoAr63e3Nj4cnv4ZP3/3EeMKERWBA2YO3IA58sAe3HHNte6hcrCul2zWMvViC0s79V6sByBkcYyTiuok0m71ywuL7True9jaNmvgqmGB1TJKSEYP3VGM4PdQ1ZcuoCLRIpPOhCOQvmbjbQPt52IDmWVRx8+1eSct0oAv6BpS6PcLcySW+0iQb7jdLKeOWBBEYOTkY3kHGelXrZpNMCLNNeXLz/8AHqZG5eMR7dgcDcCARuVXQc8A5FYUF3qF/czeXqYEcsnmPJANzKQp2naofZGDjG4gnGR7ddouha14lgURQaldG2i8iKeW5bZDwVO2RmwzneTkfdBOM4wQCNLqY3cswX7PEIdzAIY2YY4yMlmwcDLh+mc8YpL+4htNDkvrq1ubhXkV1RQiqzEMM7ipCgl9x27OMDAJFdnoPwkv4I411TU7SCBJN4trK2DMRk/emcbt2MDKheQOuK6y0+G/hyDc9xDdX87J5bz3t3JLI688Ek9OenTp6UAeTW3ito7FZrfT1ury4DMkdlH57SMTtw0g3uSu4HIkXBxjrXSWXhPxrrmmLqNy8Wl3Iz5cMin7QVwvWTezjOO8gPr0GPVtN0nTtHtvs2m2NvZwZz5cEYRc+uBVygD538R6r4ntZX0/XTeaHp8ibGWNQDcE8ECSIESMw4+Y8dTjk1r+D9e1fS9I/s3SPsc8dqXEaW9oMFycbm8vfhcnqSp4IJ5GPbLi3gu4HguYY5oXGGjkUMrfUHrXI678M9D1iyNtbG40tclljs3xDk5yTCcxk85ztznkEGgDDs/ifqNiXi1vTbe7aPGX0qdJJCOM5iDttIJHBf39cdjo3jLQde3LZX6eajeW8MoMbq+cbcHqc+ma8+uPhdqqQR2pa3vYlnJiEcnkIiAZDPvWRi5JPCED0IrG1Ozubi1itJrd40gPkLBMjeYGw20RowmlxySCoXqMY4IAPeKK8psl1+3WK+im1OCKKRWxK5ijnVeqt9plJAbI6IvJP4d74f8AE+meI0mFheW9xNbbRcC3kMiIxzwGwNw4PIHagDZooooAKKKKACiiigApks0cEZklkSNByWdgAPxqDULSS+s3gjvbizZv+WtvtDD2+YH9OfeuEu/g7o2sJnXNT1bUZiMF5LjHPrzk56d8cDjgYALup/F/wNpmQ2uw3MgbaEtFaYk57FRjt6/zrz3Xf2gLq7u5LDwto5DbtourpWkPviJO+eBz/wDW7+w+DngSwtUg/sOO4KnJluJGd2Pvzj8MYrjfGGoeF/BN02meFtIg1DxPKzOgI81LDnhtv3Vx/CoAxjnjqAYVx4k+KD3d3or6o41W6AaKKOzAeK3GQZSFBMS5OORuzjtiquh+H4Nb1C18EafCrICLjVb0MWKxDbnG48MxLL9xGHynB5qjaXF5ps9zZi0/tfxBfzM7R3tsqzNKed2QS6dccMucHGRnHu/gHwpJ4Y0Rmv5ftGs3zCfULksWZpMcLuJJIUcD8T3NAHTWttDZ2kNrbxiOCFFjjReiqBgAfgKloooA4PwBpGmz+H9SU2MURbWLwNsIEnyXD7QzqcsV7HP+J7e3tre0hEVtBHDGCTsjQKMk5JwPeuZ8FSql14msNrLJbazMzbuCRKFlBx6fPgeuM11dABRUF1e2tlC813cwwRINzPLIECj1JPSvJ/Ef7QWgaVcvBpNhcaqEO03CsI4Sf9kkEn8hQB6/RXzBqf7Q/iq73mwtNOsY92ANplfBzjknBx9PSuXl+LPj65ict4juQowCUWND3xjCg9z0/pQB9j1z/iq08K32nPF4oGnG1UZJvJFTb7hiQR1HQ96+RLDXPEGotc+b4m1RGWJpAWu3IduTglnAGctyT3PBzVO30+8u75mXNwWBAeVNxJABwQeRxjJPQc0Aek+IH8Py+IorbwYL+8tQ2CWudkBbocOQZWRQVGM4wpxnvmWN+1wt7fSyWkMAAUzYwi7hj5Ae5HHUcE8jOTy1zo1yjMBKrXMaFMRoG83naqBFHJPqeMYqrZ3Frp86SzskknlK2YwWdD024IABGAe/1OSKAO7hu7S9e2itv7RnuLl8y3EUJcyr0A2AHcAAcKW5yM9BXo+kfaP+GZ7uKVZFlis7uIrs2EBZXGGAPAwOeeBn8fE5Zb7UJ/t1pZ6mYY7dpwbu9LLtQZYgsORypx3xx1FfS9j4Z1Cb4Ow+HPtCQahNpnktIynCOy8g/mRQB5T8Q9C/4RXw5Z297PCkl+ZJU06wiYRQusZVW3sd5w0o5JA5xisu+tINJ8OtLeNeiO3h8uPEm7A4C4BAC9e+DwOpqv4i1fxL42+IdvpOs6d9hNnKsIsgxAjA5J9XDFVbODwowD36nUdObVNS0/QDbRoLy7UOwsijiMEDIItoTgAlupB2c98gHrHw70s6R4A0a3kXFxJbLPcE/eaWT52LHuctyfavF9Y+KOuH4la9JoFpbTSRqLOKabDNDBExL7FLBTubJJ/3a9y8ZayfDngrV9Vj2rJa2rNFngbyMJ/48RXylotzoWmWTySXG65dQoVU3tvBJGBjkZ28kfgeCAC9efFT4gzzqB4guEWQnafLhiB2k56DAAye/brwMX9M1rxTrUFqLrxJqLHa0jNFfSM4TJByVZY1Gc/eJbgY6Yrn2jbUteuriytA9s8ohjna2LqpxwBGTgDjOCDjHviujjC2sl1NftG0+Aiws32iUEbfnCIAijP8OR19FoA9f+C00V1ouuXEbO7NqhVpHuJJS5EMXzZfnnnn+gFeOp4l8d2Ovajpula5/Z9lDe3ISN3RkjIldioBDN1B9c/Q16/8GLlbix8Q+XbyRp/aQfdJGkZYmGPI2plV6ZwCfvc14xd30J8c683lw3KtqV0QrzM3mZmJHlxopbd/tY6E0AdNpHxM8cW6200uvQX0MjESLcacowOPu7dpbqM5xjNd1pPxEj8UXjeFvEumS6ZNcOkcV3ayl4JnB3AByBtJZCApznp1rh9E8GeJNcZWtNHuoreRAwl1Mi0g25JU+WmXc85yfQHjv6j4e+GdnYXtvqWrvb3l9bvvhSGEpDEdu0EbmZmIHHLY6HGRmgDb8c+GB4w8I3ujb0jll2vDI4yqurBhn2OMH2Jr5J1XxBqQaezux5NyjSRSwqipFGRleI1X7/X5jznB7Zr688WeKNP8I6BdapfzRKY42aGFnCtM4HCKO5Jx9OtfKN9ooia7vr/W0a5u3ZnMKli8zAv0HzbeTzwc8bfUAybp7orLbSILG1niWZkkBkZwuArc5YH8RwT24p0H9q6lvurO2WRIY9rytErMik4/i4z1wF6c/WtIReHraAXBWaO7gGApZS08rL0MQGVUYI5P8Qz79No+k3+oaPZzTtEbaaVkuLSG6W2jtl2k/vjgcFVHDuWx2+YGgDB0+OHwvqwvpvEl1DqhYGSPTl2spbGdxYdRk/LtIOM5HFe7fD7xP4u8R6tHPdabPBoPkMqS3a7HbbgAjjkk5ySx74Hqngb4Y6Lp+kx3QNv9vLZe5sl+46k58uRxuAz3AGeO1eh6dpdppcLR2iMoc7nLyM7MfUliTmgC5RRRQAUUUUAFFFFABRRRQBzfiHwZp3iC5gu3jt4r2L5RcPaxTtsySQBIpAOTnOM/UVp6NpEejWf2eOZpcnJdooo+2OkaqP0rRooAKKKKACiiigAoorH1vxTovh1U/tO/jikkOI4FBklkP+zGoLH8BQBsVnavrulaDaNdatqFtZwqM7ppAufoOpPsK58X3izxNG39n2v/AAjlg4+W6voxJdsMHlYc4j5x98k/7NX7HwVolrNJdXVt/aV/KgSW71D99I4HbnhRyeFAFAHmuufFy48SPc2Hha5tNPsUJSbUbq5RZ2XoTDFncPUMRx7GuL0jT4V1U6boFtJrF7dxiVSGjnCSFiDJcs6sFXAyVIBOfpn6Hl8I+Gp02TeHtJkTrteyjI/Vau6dpOnaPbm30ywtrKEnJjt4ljUnGMkAdcAUAc74K8Gf8I7ZpcahcG71aQFpZNxMcbHJIjB6DnGfTpgcV11FQXN7a2UZku7mGCMdWlkCjv3P0P5UAT0VgTeNvDcOP+JtDNltubYNMN3PHyA88dP8aF8WW04BstM1e7Bxyli8Y56ENJtBBHOQelAHknxK+IHiP4eePdSTTbWx8jVIYZkknjZzlUKEjBHOQOuR8o9TXm2p/F3x5rbso1me3Urjy7FBFgeuVG78c1037Qd09z4s0eSazkgAsh+6lkQufnJ5Ck4//XXl7apMIWjhAso3i8spbAgSr33Etk5xzQBof2fqOp2iXt7qUSI67VuLy4YMwyPkGScgZ3cdie/FS/2bpUemPqEst9dNFOqSzW6AwbSDhQ0gBL/L6EcHjis2AWjWsfnoSFbJBuxlhnIVQB8vU5J9SanMllcXC20OniTcu1IrMuxL88sWyXPbAwPy5AKk8ahWeOOOM4IDRvvDcc9OBkHPbGD07WZNPezkt5odwheTb9ouYAsYAxgnG7HXkdePWu48M/BbxfrC21xdWUVnaBgyDUZCDsJB/wBUvzD6EjvXqVz8CdO1I28V7qssVjb8RWljCsQA75ZixJJyc+pOOtAHz1Z3lvb6iZI1tAgkaLzTGTCAzblbaRvIGCOc8frNbTvPqTzTz2KxeaUFxNKT8q4JVR97aRxnaCd3XOa+m9I+DXgzRnaSCwllkZQu+eUuR9PTNB+Cnw/Oz/iQD5OmLqbnnv8APzQB4Vba7a6VflP7QuIookTjT4VVWU4wFYqSGA2gFtxyG+7XJDUrOJtTWytltYTzbxzsGkXDcAnYdxweRlR19gPqZfg74ISbz10mTz+CJWu5XYEYwfmYg42jqCKkPwi8Dvfz3s2iJNPOGEhlmdgcjBOM4B9wMg8g0AfLcmqXRtSZpYmNwjIZjA7SeXgqF+YbcY5BByOep4r3z4WfF3TNW0ax0bW5xaapCogSWQbYpwoAX5ugcjqDjpx1xXc23w78HWtukCeHNOkRAVU3EImYDGMbny2OemcCuM+Ldl4P8KeA7ydPDekC+vG8i1C2iKRI3V8qMjaoJz64HegDgLeObxh4+8ReJY0urmy+2i2hMdm1whVcKpZQGwNnIyhzyOM11/w600TfE7USiz/ZdIt1VHaJo1Mrg7htaNCv3n4Iz9e3HeF9LutE06GzmtbJ3dBK32vTXjmidlyUL+UHGCQMhj6gr29Q+CsVzN4Qn1i5mWT+0Ll3iCIFVUBIIHf75k680AbPj2ytNfXRvDN380Wp3oaaIOVLwxKZH5HPUIP+BDp1rn3+AvgwsvkHUYHj+ZNlyDtb+9yD6D8qf4p1PWZPjHo2naJHYyXNppM9x5d5K0aMJGCnlcnPyDHHr25HK+IfjxrPhnxDc6Pd6NpN1NauEma0u5GTPdQxUcjoeOD9KAOmk+A/ht/M26rrcYfDbY7hFUOBgNgIBkDj8TUsPwH8Fx3AkmXUrlScvFNdna/XrtAPU569a4CX9ovXJ1K2mhafE+zd88jy54xwFxg5557cVc1f40eMrK3tbj+ztGtvtRURWrLJLLz3JDAd+h9O/OAD3DRtD07w/ZGz0y2EEBbcV3sxJwFySxJ6KB+AqSy0rTtMMpsLC1tTKxeTyIVj3sepOByfevnq9+KnjfUjLb2GtabFIjfvpoLZY4oFHcyykg+4APXAJzXDal421/VdRS1udfv9RsxP5ca+eYyxB4kAXaAeeM570AfWer+KdB0CCSbVdXtLVY/vK8o3/QKPmJ56AV5P4j/aEsx+58M2Xm4G57y+QqijuFQEFjyOpFeYxRaNo8lw0KLqJZAtxNI6NsRiFkYnnncQBjPfrXP3t1Y3Gri7tJFtLaKItiCLAD5xhFcjLHcpJAGOSFAFAFvW77VfFupf2trWqvPE7OUJ4AHJCRpzj7uOBxxnNU7aGHUTKEBtIkbYcAvK65GdwXljwT/COvPGK67w38MvFHiCwB0nRX0yzmA33uoXBSSVeuFAAwp/3T/vYr1aw+Bun2wUtf8AkkqgcQwK24rj5vnym7OcNsGMn1xQB4ZptrA+oS21lp91d380e2OBgsvmOMFn2qNhUDJAyeRz1rsfB2neONWu7EDQFl0q4kWRTewYgiIUIZSvAJG3gfgFwcV7z4f8EaN4cihW2W4nkgkkkimuZS7pvADAdBj5RxjtXR0AVdOsU03TLWxjkeRLeJYldwoZgBjJ2gDP0AFWqKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigDM1q0n1Sxk0+z1V9OnfaXmgAMqx5525+6TggNg4qv4f0PQdHg8vSYbcumUkn3CSV2GM73OWJ6Zye9ab2Nq9/HftAhuo42iSXHzBCQSufTIFef3/AII1G91Ga7l8M+DZpmkZhcZmikcZ4LbUPOAM8nnNAHo7MqjLEAe5qBb60ZJHW6gKxZEjCQYTHXPpXBW3gTVBMrG08J2kakOo/s+W6dXBHRndewOMAVuaZ4d1uxMRfWrDhg0wttJSLzPbO847+/JoAmPjOyuWKaNaXussCQXsosxDHX965VD+DHpWPr/i2/0hVbVtU0Pw7FIcIJna6nP/AABdoHrn5gMDPXjqNU0mXU7OK2TVL2xC/fayKIzjHTJUlfwxXM2nwh8GwTTT3WnSalcTMWebUJ3mbrnuf16+9AHn138afDFruk+1+I9auSuSu9bSAtjGAFIIXr2b3yea5XU/jhqmpeULHQdGgdB5Uf2iFrmYrnIAY/THuTmvpG38N6HZwiG20bT4YwchI7ZFA/ACr8dvDCgSKKNFGAFVQAMdKAPn3S5vjn4k8uWCX+zbSX94jyxQwoo4I+XaXx+BzznNbLfDf4q6pamDVPHqRIeqwSSc8YxkKpxgkEV7bRQB87v+zrrT3JuLjXrO8dz8/nCRSeOu7k5+tWrP9ni8EKQXWsWkaMrLK8KO7kZJUDdgYB2nAAzg888e/UUAeXeEPgboHhm7a6vJjq0uF2i4gUIjA5yBz9MZr0Ky0TStNnlnstNtLaaU7pJIoVVmPuQPar9FABRRRQAUUUUAFFFFABXzd4s1pPH/AMSJLiN4X0bQg8duWmjCzSDqw3OuQWAIxncEHrXoHxc8aXFjaL4T0HzJdd1NdriFGdreA53PhATnAPQZAyewrl9BsYfDulW2nQ3jRQopcyPPJEHbAZiu6zODyCBuP3Qc8AgAzdbtLu30e3jNvMFvZEhi2qZFYkZZB/CW4wACvPAxjn3nQNLXRfD9hpqf8u8Koec5bHP65ryfwDott4t8dXHiJraM6Zo7mG0kMcQ+0XGeZN0SKrhB0bBPIOfT2qgD5k+Nesat4d+K013pl5LZy3GmRxmSIgMYySCM9uV+vFee3Gpa34iWGG7uvtUMKvLEroqrGSMscDAHK456nsSa9M/aPslTxXot46bY5rNoy4HLbHJI+uHH515mdaDJPa6ZAbaAxEyShR5h4AO5sEhc56cnOCfQA1vDf2G20OK4uoIJZDIdsZm3yy5JTCjgRgZ/iOTuyMgYq5f3s9j5HiLUFlgvllMdtbxzFNnzZJZ15J4IIUAA9QGJzzNpdW0NqFUxxQx5JnlXdO+7giNc4GOe+D3PavSfA/hPxJ4tdjp0b6Tojlo5dTn+a4uYjkFVP0J+7hQT+YBzltEb26SzR21S/YB4be2jMkaqCPLVUTG9Ruz0VRtIIzXo9z8F9Q8RSac1xfva2kC7i1wgEoyBhUijO1AMDOWJyO3SvYtG8P6V4ftBbaVYw20fVii/M59Wbqx9ya0qAPK9M+AfhO2Mcmpvd6nMvXfJ5SH04TBP4sTXd6d4S8O6TFHHY6JYQLGxdCsC5Vj1IJGc1s0UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABXK+PfG9l4H0Br2XZNeyny7S034aZz/wCyjqT/AFIrX17XLPw9pMmoXhYqpCRxRjdJNIeFjRf4mJ4AFebX/wAKdW8YaoniTXtcNnfyJhLD7LHcxWiHpGN/BIzktgfNkj1oA5Xw3pmpjUrrxLrjA61eu3myiSNxDGR9wLHdow7YG3IGPx1JxqmreIn8M6JdBdUuICmqX/2SeCSzibk78yurO4PHpnIINdGvws1qFESHxdblVXaGm0G1kdOcgqxGeOR+PGMV1vg/whaeENKe2imku7ydzLeXs3+suJCSSzfmcDnA9etAGloeiWHh3RrbStMgENpbrtRc5PqST3JJJJ96vkhQSSAB1JqO4uIbS2kuLiVIoYlLySOcKqjqSewrxj4n/EOa30tP3E0dteKVsbJzse7HQyzL95Yv7qcF/wCLgYoA4P43+K7XxJ4ys7W3djp1lFgSgkCUscsy8dMAAHHPXkYqDw38Lte8UWoFvEsdsY9sdz5gEKgkk7nAzM2CB8uV6jI27a6/wF8I77xRKvibx1JK63BEkVifkaQdi+MbVwMBB2Pbofe7a2hs7SG1t4xHBCixxovRVAwAPwFAHnHhn4IeFtDlgu76OTVb+LDeZcsfL3cc7M4PTvnr9MelIiRRrHGqoigBVUYAA7AU6igAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACqGs6xZaBpNxqeoS+XbQDLEDJJJwFA7kkgAepqa/v7XS7Ce+vp0gtbdDJLK54VR1NZFjZpr81hr1/byR+WnmWdpJIGWLOcSkYGJCpx1O0dOSaAKOh6RfaxqsHijxDEYZ0Vv7O04/8ALkjDBZvWVh19Og7566iigApCQoJJwB1JpssscELzTSLHFGpZ3c4CgckknoK4vU9Vt/FEUkRm+z+FomxeXsnyC+PGIYsj5kJIDN/F91chiaAM3XvEVlqmn/21qQZvDkMwXTrJBuk1i5BwmFGcpkfKuPm+8cACm+E/h9c3fiOXxr4yRZdcnffb2e4PHYqCNgBHBYAdenfrzXaQaTBd6pDrV3a7bqOHyraOTk26nluASocngkdgBnrnXoAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAMXxJBb/ZIdRu4bq6g06T7V9ktohI0zAEKdvViudwA7gHsK8cg8b+CrS5ZdK8Z+JvD6AlhaSW/nQxHPQIyPgYPAHAwO9e+1SutG0u+cvd6bZ3DkglpYFcnAwOo9KAPMYvGjxuJLb4qeHrqEk4jv7ARtgjGCUde5XsO/XaRW1ZfEHTZYmW+8XaKztEdo0y3dnDEcFdzNk/7O088dsHrY/DOgwsGi0TTUYEkFbSMHnr2q/DbQW0YjghjiQZwqKFAz16UAc9pUQh0Ge7QatrEtyT8moL5byYzgbHCqi8n+EZ688VLZaNd6heQ6lr4hLQ4a10+I7obZhyHJP35B2bAC/wjqT0NFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQB//Z" alt:@""];
}

- (UIImage *)scaleImage:(UIImage *)image toScale:(float)scaleSize
{
    UIGraphicsBeginImageContext(CGSizeMake(image.size.width * scaleSize, image.size.height * scaleSize));
                                [image drawInRect:CGRectMake(0, 0, image.size.width * scaleSize, image.size.height * scaleSize)];
                                UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
                                UIGraphicsEndImageContext();
                                
                                return scaledImage;
}

- (void)showInsertImageDialogWithLink:(NSString *)url alt:(NSString *)alt {
    
    // Insert Button Title
    NSString *insertButtonTitle = !self.selectedImageURL ? NSLocalizedString(@"Insert", nil) : NSLocalizedString(@"Update", nil);
    
    self.alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Insert Image", nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) otherButtonTitles:insertButtonTitle, nil];
    self.alertView.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
    self.alertView.tag = 1;
    UITextField *imageURL = [self.alertView textFieldAtIndex:0];
    imageURL.placeholder = NSLocalizedString(@"URL (required)", nil);
    if (url) {
        imageURL.text = url;
    }
    
    // Picker Button
    UIButton *am = [UIButton buttonWithType:UIButtonTypeCustom];
    am.frame = CGRectMake(0, 0, 25, 25);
    [am setImage:[UIImage imageNamed:@"ZSSpicker.png"] forState:UIControlStateNormal];
    [am addTarget:self action:@selector(showInsertImageAlternatePicker) forControlEvents:UIControlEventTouchUpInside];
    imageURL.rightView = am;
    imageURL.rightViewMode = UITextFieldViewModeAlways;
    imageURL.clearButtonMode = UITextFieldViewModeAlways;
    
    UITextField *alt1 = [self.alertView textFieldAtIndex:1];
    alt1.secureTextEntry = NO;
    UIView *test = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    test.backgroundColor = [UIColor redColor];
    alt1.rightView = test;
    alt1.placeholder = NSLocalizedString(@"Alt", nil);
    alt1.clearButtonMode = UITextFieldViewModeAlways;
    if (alt) {
        alt1.text = alt;
    }
    
    [self.alertView show];
    
}

- (void)insertImage:(NSString *)url alt:(NSString *)alt {
    NSString *trigger = [NSString stringWithFormat:@"zss_editor.insertImage(\"%@\", \"%@\");", url, alt];
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}


- (void)updateImage:(NSString *)url alt:(NSString *)alt {
    NSString *trigger = [NSString stringWithFormat:@"zss_editor.updateImage(\"%@\", \"%@\");", url, alt];
    [self.editorView stringByEvaluatingJavaScriptFromString:trigger];
}


- (void)updateToolBarWithButtonName:(NSString *)name {
    
    // Items that are enabled
    NSArray *itemNames = [name componentsSeparatedByString:@","];
    
    // Special case for link
    NSMutableArray *itemsModified = [[NSMutableArray alloc] init];
    for (NSString *linkItem in itemNames) {
        NSString *updatedItem = linkItem;
        if ([linkItem hasPrefix:@"link:"]) {
            updatedItem = @"link";
            self.selectedLinkURL = [linkItem stringByReplacingOccurrencesOfString:@"link:" withString:@""];
        } else if ([linkItem hasPrefix:@"link-title:"]) {
            self.selectedLinkTitle = [self stringByDecodingURLFormat:[linkItem stringByReplacingOccurrencesOfString:@"link-title:" withString:@""]];
        } else if ([linkItem hasPrefix:@"image:"]) {
            updatedItem = @"image";
            self.selectedImageURL = [linkItem stringByReplacingOccurrencesOfString:@"image:" withString:@""];
        } else if ([linkItem hasPrefix:@"image-alt:"]) {
            self.selectedImageAlt = [self stringByDecodingURLFormat:[linkItem stringByReplacingOccurrencesOfString:@"image-alt:" withString:@""]];
        } else {
            self.selectedImageURL = nil;
            self.selectedImageAlt = nil;
            self.selectedLinkURL = nil;
            self.selectedLinkTitle = nil;
        }
        [itemsModified addObject:updatedItem];
    }
    itemNames = [NSArray arrayWithArray:itemsModified];
   
    self.editorItemsEnabled = itemNames;
    
    // Highlight items
    NSArray *items = self.toolbar.items;
    for (ZSSBarButtonItem *item in items) {
        if ([itemNames containsObject:item.label]) {
            item.tintColor = [self barButtonItemSelectedDefaultColor];
        } else {
            item.tintColor = [self barButtonItemDefaultColor];
        }
    }//end
    
}
    

#pragma mark - UITextView Delegate
    
- (void)textViewDidChange:(UITextView *)textView {
    CGRect line = [textView caretRectForPosition:textView.selectedTextRange.start];
    CGFloat overflow = line.origin.y + line.size.height - ( textView.contentOffset.y + textView.bounds.size.height - textView.contentInset.bottom - textView.contentInset.top );
    if ( overflow > 0 ) {
        // We are at the bottom of the visible text and introduced a line feed, scroll down (iOS 7 does not do it)
        // Scroll caret to visible area
        CGPoint offset = textView.contentOffset;
        offset.y += overflow + 7; // leave 7 pixels margin
        // Cannot animate with setContentOffset:animated: or caret will not appear
        [UIView animateWithDuration:.2 animations:^{
            [textView setContentOffset:offset];
        }];
    }
}


#pragma mark - UIWebView Delegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    
    NSString *urlString = [[request URL] absoluteString];
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
		return NO;
	} else if ([urlString rangeOfString:@"callback://"].location != NSNotFound) {
        
        // We recieved the callback
        NSString *className = [urlString stringByReplacingOccurrencesOfString:@"callback://" withString:@""];
        [self updateToolBarWithButtonName:className];
        
    } else if ([urlString rangeOfString:@"debug://"].location != NSNotFound) {
        
        // We recieved the callback
        NSString *debug = [urlString stringByReplacingOccurrencesOfString:@"debug://" withString:@""];
        debug = [debug stringByReplacingPercentEscapesUsingEncoding:NSStringEncodingConversionAllowLossy];
        NSLog(@"%@", debug);
        
    } else if ([urlString rangeOfString:@"scroll://"].location != NSNotFound) {
        
        NSInteger position = [[urlString stringByReplacingOccurrencesOfString:@"scroll://" withString:@""] integerValue];
        [self editorDidScrollWithPosition:position];
        
    }
    
    return YES;
    
}//end


- (void)webViewDidFinishLoad:(UIWebView *)webView {
    self.editorLoaded = YES;
    //[self setPlaceholderText];
    if (!self.internalHTML) {
        self.internalHTML = @"";
    }
    [self updateHTML];
    if (self.shouldShowKeyboard) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self focusTextEditor];
        });
    }
}


#pragma mark - Callbacks

// Blank implementation
- (void)editorDidScrollWithPosition:(NSInteger)position {
    
    
}


#pragma mark - AlertView

- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alertView {
    
    if (alertView.tag == 1) {
        UITextField *textField = [alertView textFieldAtIndex:0];
        UITextField *textField2 = [alertView textFieldAtIndex:1];
        if ([textField.text length] == 0 || [textField2.text length] == 0) {
            return NO;
        }
    } else if (alertView.tag == 2) {
        UITextField *textField = [alertView textFieldAtIndex:0];
        if ([textField.text length] == 0) {
            return NO;
        }
    }
    
    return YES;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    if (alertView.tag == 1) {
        if (buttonIndex == 1) {
            UITextField *imageURL = [alertView textFieldAtIndex:0];
            UITextField *alt = [alertView textFieldAtIndex:1];
            if (!self.selectedImageURL) {
                [self insertImage:imageURL.text alt:alt.text];
            } else {
                [self updateImage:imageURL.text alt:alt.text];
            }
        }
    } else if (alertView.tag == 2) {
        if (buttonIndex == 1) {
            UITextField *linkURL = [alertView textFieldAtIndex:0];
            UITextField *title = [alertView textFieldAtIndex:1];
            if (!self.selectedLinkURL) {
                [self insertLink:linkURL.text title:title.text];
            } else {
                [self updateLink:linkURL.text title:title.text];
            }
        }
    }
    
}


#pragma mark - Asset Picker

- (void)showInsertURLAlternatePicker {
    // Blank method. User should implement this in their subclass
}


- (void)showInsertImageAlternatePicker {
    // Blank method. User should implement this in their subclass
}


#pragma mark - Keyboard status
-(void)keyboardWillChangeFrame:(NSNotification*)notif{

    
    NSDictionary *info = notif.userInfo;
    //NSLog(@"%@", keyboardBoundsValue);
    CGFloat duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    CGRect rect = [[[notif userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    
    //NSLog(@"%@", NSStringFromCGRect(rect));
    
    [UIView animateWithDuration:duration animations:^{
        CGRect frame = _toolbarHolder.frame;
        _toolbarHolder.alpha = 1;
        //Change to fit PIXNET custom View form Cloud
        
        _toolbarHolder.frame = CGRectMake(0, rect.origin.y-20-44-44-45, frame.size.width, frame.size.height);
        
    }];
    
}


- (void)keyboardWillShowOrHide:(NSNotification *)notification {
    
    // User Info
    NSDictionary *info = notification.userInfo;
    CGFloat duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    
    if ([notification.name isEqualToString:UIKeyboardWillShowNotification]) {
        _isFocusTextEditor = YES;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"editorKeyboardStatus" object:_isFocusTextEditor? [NSNumber numberWithBool:YES]:[NSNumber numberWithBool:NO]];
        
        [UIView animateWithDuration:duration animations:^{
            _toolbarHolder.alpha = 1;
        }];
    } else {
        _isFocusTextEditor = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"editorKeyboardStatus" object:_isFocusTextEditor? [NSNumber numberWithBool:YES]:[NSNumber numberWithBool:NO]];
        [UIView animateWithDuration:duration animations:^{
            _toolbarHolder.alpha = 0;
        }];
    }
}


#pragma mark - Utilities

- (NSString *)removeQuotesFromHTML:(NSString *)html {
    html = [html stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    html = [html stringByReplacingOccurrencesOfString:@"“" withString:@"&quot;"];
    html = [html stringByReplacingOccurrencesOfString:@"”" withString:@"&quot;"];
    html = [html stringByReplacingOccurrencesOfString:@"\r"  withString:@"\\r"];
    html = [html stringByReplacingOccurrencesOfString:@"\n"  withString:@"\\n"];
    return html;
}//end


- (NSString *)tidyHTML:(NSString *)html {
    html = [html stringByReplacingOccurrencesOfString:@"<br>" withString:@"<br />"];
    html = [html stringByReplacingOccurrencesOfString:@"<hr>" withString:@"<hr />"];
    if (self.formatHTML) {
        html = [self.editorView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"style_html(\"%@\");", html]];
    }
    return html;
}//end


- (UIColor *)barButtonItemDefaultColor {
    
    if (self.toolbarItemTintColor) {
        return self.toolbarItemTintColor;
    }
    
    return [UIColor colorWithRed:0.0f/255.0f green:122.0f/255.0f blue:255.0f/255.0f alpha:1.0f];
}


- (UIColor *)barButtonItemSelectedDefaultColor {
    
    if (self.toolbarItemSelectedTintColor) {
        return self.toolbarItemSelectedTintColor;
    }
    
    return [UIColor blackColor];
}


- (BOOL)isIpad {
	return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
}//end


- (NSString *)stringByDecodingURLFormat:(NSString *)string {
    NSString *result = [string stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    result = [result stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return result;
}
    

- (void)enableToolbarItems:(BOOL)enable {
    NSArray *items = self.toolbar.items;
    for (ZSSBarButtonItem *item in items) {
        if (![item.label isEqualToString:@"source"]) {
            item.enabled = enable;
        }
    }
}


@end
