#import "I2FControlPanelViewController.h"

#import "I2FConfigManager.h"
#import "I2FDumpRvaParser.h"
#import "I2FTextLogManager.h"
#import "I2FIl2CppTextHookManager.h"
#import "includes/SDAutoLayout/SDAutoLayout.h"

@interface I2FControlPanelViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *autoDumpLabel;
@property (nonatomic, strong) UISwitch *autoDumpSwitch;
@property (nonatomic, strong) UILabel *autoHookLabel;
@property (nonatomic, strong) UISwitch *autoHookSwitch;
@property (nonatomic, strong) UILabel *hookAfterDumpLabel;
@property (nonatomic, strong) UISwitch *hookAfterDumpSwitch;
@property (nonatomic, strong) UIButton *resetDumpButton;
@property (nonatomic, strong) UIButton *reparseButton;
@property (nonatomic, strong) UIButton *clearHookButton;
@property (nonatomic, strong) UIButton *clearLogButton;
@property (nonatomic, strong) UILabel *rvaLabel;
@property (nonatomic, strong) UITableView *hookTableView;
@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) NSArray<I2FTextLogEntry *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *hookEntries;

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

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    [container addSubview:scroll];
    self.scrollView = scroll;

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.titleLabel.text = @"I2Fusion 控制面板";

    self.autoDumpSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.autoDumpSwitch.on = [I2FConfigManager autoDumpEnabled];
    [self.autoDumpSwitch addTarget:self action:@selector(autoDumpSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    self.autoDumpLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.autoDumpLabel.textColor = [UIColor lightGrayColor];
    self.autoDumpLabel.font = [UIFont systemFontOfSize:13];
    self.autoDumpLabel.text = @"启动时自动 dump";

    self.autoHookSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.autoHookSwitch.on = [I2FConfigManager autoInstallHookOnLaunch];
    [self.autoHookSwitch addTarget:self action:@selector(autoHookSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    self.autoHookLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.autoHookLabel.textColor = [UIColor lightGrayColor];
    self.autoHookLabel.font = [UIFont systemFontOfSize:13];
    self.autoHookLabel.text = @"启动时自动安装 set_Text hook";

    self.hookAfterDumpSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.hookAfterDumpSwitch.on = [I2FConfigManager autoInstallHookAfterDump];
    [self.hookAfterDumpSwitch addTarget:self action:@selector(hookAfterDumpSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    self.hookAfterDumpLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hookAfterDumpLabel.textColor = [UIColor lightGrayColor];
    self.hookAfterDumpLabel.font = [UIFont systemFontOfSize:13];
    self.hookAfterDumpLabel.text = @"dump 成功后自动安装最新 hook";

    self.resetDumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetDumpButton setTitle:@"重置 dump 标记" forState:UIControlStateNormal];
    [self.resetDumpButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.resetDumpButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.resetDumpButton addTarget:self action:@selector(resetDumpTapped) forControlEvents:UIControlEventTouchUpInside];

    self.reparseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.reparseButton setTitle:@"重新解析 dump.cs" forState:UIControlStateNormal];
    [self.reparseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.reparseButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.reparseButton addTarget:self action:@selector(reparseTapped) forControlEvents:UIControlEventTouchUpInside];

    self.clearHookButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearHookButton setTitle:@"清空 hook 列表" forState:UIControlStateNormal];
    [self.clearHookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearHookButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.clearHookButton addTarget:self action:@selector(clearHookTapped) forControlEvents:UIControlEventTouchUpInside];

    self.clearLogButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearLogButton setTitle:@"清空日志" forState:UIControlStateNormal];
    [self.clearLogButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearLogButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.clearLogButton addTarget:self action:@selector(clearLogTapped) forControlEvents:UIControlEventTouchUpInside];

    self.rvaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.rvaLabel.textColor = [UIColor lightGrayColor];
    self.rvaLabel.font = [UIFont systemFontOfSize:12];

    self.hookTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.hookTableView.dataSource = self;
    self.hookTableView.delegate = self;
    self.hookTableView.backgroundColor = [UIColor clearColor];
    self.hookTableView.separatorColor = [UIColor darkGrayColor];
    self.hookTableView.scrollEnabled = YES;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor darkGrayColor];

    [self buildLeftStackLayout];
    [self buildRightLogLayout];
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

- (UIView *)addSwitchRowWithLabel:(UILabel *)label
                    switchControl:(UISwitch *)switchControl
                          topView:(UIView *)topView
                          padding:(CGFloat)padding {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:row];
    if (topView) {
        row.sd_layout.leftSpaceToView(self.scrollView, padding)
                     .rightSpaceToView(self.scrollView, padding)
                     .topSpaceToView(topView, padding)
                     .heightIs(36.0);
    } else {
        row.sd_layout.leftSpaceToView(self.scrollView, padding)
                     .rightSpaceToView(self.scrollView, padding)
                     .topSpaceToView(self.scrollView, padding)
                     .heightIs(36.0);
    }

    [row addSubview:label];
    [row addSubview:switchControl];

    [switchControl sizeToFit];
    CGFloat switchWidth = MAX(50.0, switchControl.bounds.size.width);
    CGFloat switchHeight = MAX(30.0, switchControl.bounds.size.height);

    switchControl.sd_layout.rightSpaceToView(row, 0)
                           .centerYEqualToView(row)
                           .widthIs(switchWidth)
                           .heightIs(switchHeight);
    label.sd_layout.leftSpaceToView(row, 0)
                    .centerYEqualToView(row)
                    .rightSpaceToView(switchControl, 8.0)
                    .heightIs(20.0);
    return row;
}

- (UIView *)addButtonRowWithLeft:(UIButton *)leftButton
                           right:(UIButton *)rightButton
                          topView:(UIView *)topView
                          padding:(CGFloat)padding {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:row];
    row.sd_layout.leftSpaceToView(self.scrollView, padding)
                 .rightSpaceToView(self.scrollView, padding)
                 .topSpaceToView(topView, padding)
                 .heightIs(32.0);

    [row addSubview:leftButton];
    [row addSubview:rightButton];

    leftButton.sd_layout.leftSpaceToView(row, 0)
                        .topSpaceToView(row, 0)
                        .bottomSpaceToView(row, 0)
                        .widthRatioToView(row, 0.48);
    rightButton.sd_layout.rightSpaceToView(row, 0)
                         .topSpaceToView(row, 0)
                         .bottomSpaceToView(row, 0)
                         .widthRatioToView(row, 0.48);
    return row;
}

- (void)buildLeftStackLayout {
    CGFloat padding = 12.0;
    UIScrollView *scroll = self.scrollView;

    [scroll addSubview:self.titleLabel];
    self.titleLabel.sd_layout.leftSpaceToView(scroll, padding)
                           .rightSpaceToView(scroll, padding)
                           .topSpaceToView(scroll, padding)
                           .heightIs(22.0);

    UIView *row1 = [self addSwitchRowWithLabel:self.autoDumpLabel
                                  switchControl:self.autoDumpSwitch
                                        topView:self.titleLabel
                                        padding:10.0];
    UIView *row2 = [self addSwitchRowWithLabel:self.autoHookLabel
                                  switchControl:self.autoHookSwitch
                                        topView:row1
                                        padding:8.0];
    UIView *row3 = [self addSwitchRowWithLabel:self.hookAfterDumpLabel
                                  switchControl:self.hookAfterDumpSwitch
                                        topView:row2
                                        padding:8.0];

    UIView *btnRow1 = [self addButtonRowWithLeft:self.resetDumpButton
                                           right:self.reparseButton
                                          topView:row3
                                          padding:12.0];
    UIView *btnRow2 = [self addButtonRowWithLeft:self.clearHookButton
                                           right:self.clearLogButton
                                          topView:btnRow1
                                          padding:8.0];

    [scroll addSubview:self.rvaLabel];
    self.rvaLabel.sd_layout.leftSpaceToView(scroll, padding)
                           .rightSpaceToView(scroll, padding)
                           .topSpaceToView(btnRow2, 12.0)
                           .heightIs(18.0);

    [scroll addSubview:self.hookTableView];
    self.hookTableView.sd_layout.leftEqualToView(self.rvaLabel)
                                .rightEqualToView(self.rvaLabel)
                                .topSpaceToView(self.rvaLabel, 8.0)
                                .heightIs(180.0);

    [scroll setupAutoContentSizeWithBottomView:self.hookTableView bottomMargin:padding];
}

- (void)buildRightLogLayout {
    [self.containerView addSubview:self.tableView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.view.userInteractionEnabled = YES;
    [self applyOrientationLayout];
}

- (void)applyOrientationLayout {
    if (!self.containerView) {
        return;
    }

    CGSize size = self.view.bounds.size;
    BOOL isLandscape = size.width > size.height;

    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.view.safeAreaInsets;
    }

    [self.containerView sd_resetLayout];
    if (isLandscape) {
        self.containerView.sd_layout.topSpaceToView(self.view, safeInsets.top)
                                  .bottomSpaceToView(self.view, safeInsets.bottom)
                                  .rightSpaceToView(self.view, 0)
                                  .widthRatioToView(self.view, 0.75);
    } else {
        self.containerView.sd_layout.leftSpaceToView(self.view, 0)
                                  .rightSpaceToView(self.view, 0)
                                  .bottomSpaceToView(self.view, safeInsets.bottom)
                                  .heightRatioToView(self.view, 0.75);
    }

    CGFloat padding = 16.0;

    [self.scrollView sd_resetLayout];
    [self.tableView sd_resetLayout];

    if (isLandscape) {
        self.scrollView.sd_layout.leftSpaceToView(self.containerView, padding)
                                .topSpaceToView(self.containerView, padding)
                                .bottomSpaceToView(self.containerView, padding)
                                .widthRatioToView(self.containerView, 0.5);

        self.tableView.sd_layout.leftSpaceToView(self.scrollView, padding)
                               .rightSpaceToView(self.containerView, padding)
                               .topEqualToView(self.scrollView)
                               .bottomEqualToView(self.scrollView);
    } else {
        self.scrollView.sd_layout.leftSpaceToView(self.containerView, padding)
                                .rightSpaceToView(self.containerView, padding)
                                .topSpaceToView(self.containerView, padding)
                                .heightRatioToView(self.containerView, 0.45);

        self.tableView.sd_layout.leftEqualToView(self.scrollView)
                               .rightEqualToView(self.scrollView)
                               .topSpaceToView(self.scrollView, padding)
                               .bottomSpaceToView(self.containerView, padding);
    }

    [self.view layoutIfNeeded];
    // 强制 SDAutoLayout 计算各视图 frame，确保容器和子视图在旋转后可见。
    [self.containerView updateLayout];
    [self.scrollView updateLayout];
    [self.tableView updateLayout];
}

- (void)reloadData {
    self.entries = [[I2FTextLogManager sharedManager] allEntries];
    NSArray<NSDictionary *> *entries = [I2FConfigManager setTextHookEntries];
    self.hookEntries = entries;
    if (entries.count > 0) {
        NSString *firstName = entries.firstObject[@"name"] ?: @"(未命名)";
        self.rvaLabel.text = [NSString stringWithFormat:@"当前 set_Text hook: %@ 等 %lu 个", firstName, (unsigned long)entries.count];
    } else {
        self.rvaLabel.text = @"当前 set_Text hook: 未配置";
    }
    [self.hookTableView reloadData];
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

- (BOOL)isHookActiveForEntry:(NSDictionary *)entry {
    id enabledObj = entry[@"enabled"];
    if ([enabledObj respondsToSelector:@selector(boolValue)]) {
        return [enabledObj boolValue];
    }
    return YES;
}

- (void)hookSwitchChanged:(UISwitch *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.hookEntries.count) {
        return;
    }
    NSDictionary *entry = self.hookEntries[row];
    BOOL enabled = sender.isOn;

    // 更新存储
    NSMutableArray<NSDictionary *> *updated = [self.hookEntries mutableCopy];
    NSMutableDictionary *mutableEntry = [entry mutableCopy];
    mutableEntry[@"enabled"] = @(enabled);
    updated[row] = [mutableEntry copy];
    [I2FConfigManager setSetTextHookEntries:updated];
    self.hookEntries = [I2FConfigManager setTextHookEntries];

    // 运行时安装/卸载（若 base 已知）
    if (enabled) {
        [I2FIl2CppTextHookManager installHooksWithEntries:@[mutableEntry]];
    } else {
        [I2FIl2CppTextHookManager uninstallHooksWithEntries:@[mutableEntry]];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hookTableView reloadData];
    });
}

- (void)autoDumpSwitchChanged:(UISwitch *)sender {
    [I2FConfigManager setAutoDumpEnabled:sender.isOn];
}

- (void)autoHookSwitchChanged:(UISwitch *)sender {
    [I2FConfigManager setAutoInstallHookOnLaunch:sender.isOn];
}

- (void)hookAfterDumpSwitchChanged:(UISwitch *)sender {
    [I2FConfigManager setAutoInstallHookAfterDump:sender.isOn];
}

- (void)resetDumpTapped {
    [I2FConfigManager resetDumpFlags];
}

- (void)clearHookTapped {
    [I2FConfigManager setSetTextHookEntries:@[]];
    [self reloadData];
}

- (void)clearLogTapped {
    [[I2FTextLogManager sharedManager] clear];
}

- (void)reparseTapped {
    NSString *dumpPath = [I2FConfigManager lastDumpDirectory];
    if (dumpPath.length == 0) {
        [self reloadData];
        return;
    }

    NSArray<NSDictionary *> *entries = [I2FDumpRvaParser allSetTextEntriesInDumpDirectory:dumpPath];
    if (entries.count == 0) {
        [self reloadData];
        return;
    }

    [I2FConfigManager setSetTextHookEntries:entries];
    [I2FIl2CppTextHookManager installHooksWithEntries:entries];

    [self reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.hookTableView) {
        return self.hookEntries.count;
    }
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.hookTableView) {
        static NSString *hookCellId = @"I2FHookCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:hookCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:hookCellId];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = [UIColor whiteColor];
            cell.detailTextLabel.textColor = [UIColor lightGrayColor];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:12];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:10];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.numberOfLines = 1;
            cell.detailTextLabel.numberOfLines = 2;
        }
        NSDictionary *hook = self.hookEntries[indexPath.row];
        NSString *name = hook[@"name"];
        NSString *rva = hook[@"rva"] ?: @"";
        NSString *signature = hook[@"signature"];
        cell.textLabel.text = name.length > 0 ? name : @"(未命名)";
        if (signature.length > 0) {
            cell.detailTextLabel.text = signature;
        } else if (rva.length > 0) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"RVA: %@", rva];
        } else {
            cell.detailTextLabel.text = @"";
        }
        UISwitch *toggle = nil;
        if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
            toggle = (UISwitch *)cell.accessoryView;
        } else {
            toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
            cell.accessoryView = toggle;
        }
        toggle.tag = indexPath.row;
        [toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [toggle addTarget:self action:@selector(hookSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        toggle.on = [self isHookActiveForEntry:hook];
        return cell;
    }

    static NSString *cellId = @"I2FTextCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.textLabel.numberOfLines = 2;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    I2FTextLogEntry *entry = self.entries[indexPath.row];
    cell.textLabel.text = entry.text;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *time = [fmt stringFromDate:entry.timestamp];
    NSString *label = entry.rvaString.length > 0 ? entry.rvaString : @"(未知方法)";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"[%@] %@", time, label];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 40.0;
}

@end
