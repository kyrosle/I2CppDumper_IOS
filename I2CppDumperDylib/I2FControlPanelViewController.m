#import "I2FControlPanelViewController.h"

#import "I2FConfigManager.h"
#import "I2FDumpRvaParser.h"
#import "I2FTextLogManager.h"
#import "I2FIl2CppTextHookManager.h"

@interface I2FControlPanelViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *autoDumpLabel;
@property (nonatomic, strong) UISwitch *autoDumpSwitch;
@property (nonatomic, strong) UIButton *resetDumpButton;
@property (nonatomic, strong) UIButton *reparseButton;
@property (nonatomic, strong) UIButton *clearLogButton;
@property (nonatomic, strong) UILabel *rvaLabel;
@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, copy) NSString *currentRvaString;
@property (nonatomic, strong) NSArray<I2FTextLogEntry *> *entries;

@end

@implementation I2FControlPanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:container];
    self.containerView = container;

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.titleLabel.text = @"I2Fusion 控制面板";
    [container addSubview:self.titleLabel];

    self.autoDumpSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.autoDumpSwitch.on = [I2FConfigManager autoDumpEnabled];
    [self.autoDumpSwitch addTarget:self action:@selector(autoDumpSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.autoDumpSwitch];

    self.autoDumpLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.autoDumpLabel.textColor = [UIColor lightGrayColor];
    self.autoDumpLabel.font = [UIFont systemFontOfSize:13];
    self.autoDumpLabel.text = @"启动时自动 dump（仅控制 dump，hook 始终开启）";
    [container addSubview:self.autoDumpLabel];

    self.resetDumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetDumpButton setTitle:@"重置 dump 标记" forState:UIControlStateNormal];
    [self.resetDumpButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.resetDumpButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.resetDumpButton addTarget:self action:@selector(resetDumpTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.resetDumpButton];

    self.reparseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.reparseButton setTitle:@"重新解析 dump.cs" forState:UIControlStateNormal];
    [self.reparseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.reparseButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.reparseButton addTarget:self action:@selector(reparseTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.reparseButton];

    self.clearLogButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearLogButton setTitle:@"清空日志" forState:UIControlStateNormal];
    [self.clearLogButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearLogButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.clearLogButton addTarget:self action:@selector(clearLogTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.clearLogButton];

    self.rvaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.rvaLabel.textColor = [UIColor lightGrayColor];
    self.rvaLabel.font = [UIFont systemFontOfSize:12];
    [container addSubview:self.rvaLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor darkGrayColor];
    [container addSubview:self.tableView];

    [self reloadData];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textLogDidAppend:)
                                                 name:I2FTextLogManagerDidAppendEntryNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textLogDidClear:)
                                                 name:I2FTextLogManagerDidClearNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.view.userInteractionEnabled = YES;

    if (!self.containerView) {
        return;
    }

    CGSize size = self.view.bounds.size;
    BOOL isLandscape = size.width > size.height;

    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.view.safeAreaInsets;
    }

    if (isLandscape) {
        CGFloat width = size.width * 0.4;
        self.containerView.frame = CGRectMake(size.width - width,
                                              safeInsets.top,
                                              width,
                                              size.height - safeInsets.top - safeInsets.bottom);
    } else {
        CGFloat height = size.height * 0.5;
        self.containerView.frame = CGRectMake(0,
                                              size.height - height - safeInsets.bottom,
                                              size.width,
                                              height);
    }

    CGRect bounds = self.containerView.bounds;
    CGFloat padding = 16.0;

    CGFloat y = 12.0;
    CGFloat switchWidth = self.autoDumpSwitch.bounds.size.width;
    CGFloat switchHeight = self.autoDumpSwitch.bounds.size.height;

    self.titleLabel.frame = CGRectMake(padding,
                                       y,
                                       bounds.size.width - padding * 3 - switchWidth,
                                       24.0);

    self.autoDumpSwitch.frame = CGRectMake(CGRectGetMaxX(self.titleLabel.frame) + padding,
                                           y,
                                           switchWidth,
                                           switchHeight);

    y = CGRectGetMaxY(self.titleLabel.frame) + 8.0;
    self.autoDumpLabel.frame = CGRectMake(padding,
                                          y,
                                          bounds.size.width - padding * 2,
                                          20.0);

    y = CGRectGetMaxY(self.autoDumpLabel.frame) + 8.0;
    CGFloat buttonHeight = 28.0;
    CGFloat buttonWidth = 120.0;
    self.resetDumpButton.frame = CGRectMake(padding,
                                            y,
                                            buttonWidth,
                                            buttonHeight);

    self.reparseButton.frame = CGRectMake(CGRectGetMaxX(self.resetDumpButton.frame) + 12.0,
                                          y,
                                          buttonWidth,
                                          buttonHeight);

    self.clearLogButton.frame = CGRectMake(CGRectGetMaxX(self.reparseButton.frame) + 12.0,
                                           y,
                                           buttonWidth,
                                           buttonHeight);

    y = CGRectGetMaxY(self.resetDumpButton.frame) + 8.0;
    self.rvaLabel.frame = CGRectMake(padding,
                                     y,
                                     bounds.size.width - padding * 2,
                                     18.0);

    CGFloat tableTop = CGRectGetMaxY(self.rvaLabel.frame) + 8.0;
    self.tableView.frame = CGRectMake(0,
                                      tableTop,
                                      bounds.size.width,
                                      bounds.size.height - tableTop);
}

- (void)reloadData {
    self.entries = [[I2FTextLogManager sharedManager] allEntries];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storedRva = [defaults stringForKey:@"I2F.SetTextRvaString"];
    NSArray<NSString *> *allRvas = [defaults arrayForKey:@"I2F.SetTextRvaStrings"];
    self.currentRvaString = storedRva ?: @"未解析";
    if (allRvas.count > 1) {
        self.rvaLabel.text = [NSString stringWithFormat:@"当前 set_Text RVA: %@ 等 %lu 个", self.currentRvaString, (unsigned long)allRvas.count];
    } else {
        self.rvaLabel.text = [NSString stringWithFormat:@"当前 set_Text RVA: %@", self.currentRvaString];
    }
    [self.tableView reloadData];
}

- (void)textLogDidAppend:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadData];
        if (self.entries.count > 0) {
            NSIndexPath *first = [NSIndexPath indexPathForRow:0 inSection:0];
            if ([self.tableView numberOfRowsInSection:0] > 0) {
                [self.tableView scrollToRowAtIndexPath:first atScrollPosition:UITableViewScrollPositionTop animated:YES];
            }
        }
    });
}

- (void)textLogDidClear:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadData];
    });
}

- (void)autoDumpSwitchChanged:(UISwitch *)sender {
    [I2FConfigManager setAutoDumpEnabled:sender.isOn];
}

- (void)resetDumpTapped {
    [I2FConfigManager resetDumpFlags];
}

- (void)clearLogTapped {
    [[I2FTextLogManager sharedManager] clear];
}

- (void)reparseTapped {
    NSString *dumpPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"I2F.LastDumpDirectory"];
    if (dumpPath.length == 0) {
        [self reloadData];
        return;
    }

    NSArray<NSString *> *allRvas = [I2FDumpRvaParser allSetTextRvaStringsInDumpDirectory:dumpPath];
    if (allRvas.count == 0) {
        [self reloadData];
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:allRvas forKey:@"I2F.SetTextRvaStrings"];
    NSString *firstRva = allRvas.firstObject;
    [defaults setObject:firstRva forKey:@"I2F.SetTextRvaString"];
    [defaults synchronize];

    extern unsigned long long I2FCurrentIl2CppBaseAddress(void);
    unsigned long long base = I2FCurrentIl2CppBaseAddress();
    if (base != 0) {
        [I2FIl2CppTextHookManager installHooksWithBaseAddress:base rvaStrings:allRvas];
    }

    [self reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"I2FTextCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.textLabel.numberOfLines = 2;
    }
    I2FTextLogEntry *entry = self.entries[indexPath.row];
    cell.textLabel.text = entry.text;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *time = [fmt stringFromDate:entry.timestamp];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"[%@] RVA: %@", time, entry.rvaString];
    return cell;
}

@end
