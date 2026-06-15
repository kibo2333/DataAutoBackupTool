using System;
using System.Drawing;
using System.Windows.Forms;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Threading;
using System.Text;

public class DataBackupTool : Form
{
    private TabControl 备份记录;
    private TabPage tabPage3;
    private TabPage tabPage4;
    private DataGridView dataGridView1;
    private Button buttonClearRecords;
    
    private GroupBox groupBox1;
    private Label label1;
    private TextBox textBox1;
    private ComboBox comboBox1;
    private Button button1;
    private Button button2;
    private Panel panel1;
    private Label label2;
    
    private TabControl tabControl1;
    private TabPage tabPage1;
    private TabPage tabPage2;
    
    private Label label3;
    private DateTimePicker dateTimePicker1;
    private Label label4;
    private TextBox textBox3;
    private Button button3;
    private Label label5;
    private RadioButton radioButton1;
    private RadioButton radioButton2;
    private RadioButton radioButton3;
    private Label label6;
    private RadioButton radioButton5;
    private RadioButton radioButton6;
    private CheckBox checkBox1;
    private Button button5;
    
    private Button button6;
    private Label label8;
    private Panel panelDuplicateOption;
    private RadioButton radioButton11;
    private RadioButton radioButton12;
    private RadioButton radioButton13;
    private Label label9;
    private RadioButton radioButton14;
    private RadioButton radioButton15;
    private Label label10;
    private TextBox textBox4;
    private Button button7;
    private Button button9;
    
    private GroupBox groupBox2;
    private Button button4;
    private TextBox textBox2;
    
    // 数据库配置控件 - 备份数据库
    private Label labelBackupDbHost;
    private TextBox textBoxBackupDbHost;
    private Label labelBackupDbPort;
    private TextBox textBoxBackupDbPort;
    private Label labelBackupDbUser;
    private TextBox textBoxBackupDbUser;
    private Label labelBackupDbPassword;
    private TextBox textBoxBackupDbPassword;
    private Label labelBackupDbName;
    private TextBox textBoxBackupDbName;
    private Button buttonTestBackupConnection;
    private Button buttonSaveBackupDbConfig;
    private Label labelBackupConnectionStatus;
    
    // 数据库配置控件 - 导入数据库
    private Label labelImportDbHost;
    private TextBox textBoxImportDbHost;
    private Label labelImportDbPort;
    private TextBox textBoxImportDbPort;
    private Label labelImportDbUser;
    private TextBox textBoxImportDbUser;
    private Label labelImportDbPassword;
    private TextBox textBoxImportDbPassword;
    private Label labelImportDbName;
    private TextBox textBoxImportDbName;
    private Button buttonTestImportConnection;
    private Button buttonSaveImportDbConfig;
    private Label labelImportConnectionStatus;
    
    private TabPage tabPageDbConfig;  // 数据库配置标签页

    private static volatile bool isWorking = false;
    private static System.Diagnostics.Process currentProcess = null;
    private static readonly object stateLock = new object();
    private static System.Threading.Mutex backupMutex = null;  // 互斥锁，确保只有一个备份进程运行
    // 本程序启动的子进程 PID 集合，用于精确终止（仅终止自己的进程，不影响系统其他进程）
    private static System.Collections.Generic.HashSet<int> childProcessPids = new System.Collections.Generic.HashSet<int>();
    private static object pidLock = new object();
    // 全局取消信号，用于跨进程通知自动备份终止
    private static System.Threading.EventWaitHandle cancelEventHandle = null;
    private const string CancelEventName = "Global\\DataBackupTool_Cancel";
    
    private FileSystemWatcher logWatcher;
    private string logFilePath;
    private long lastFileSize = 0;
    
    private static string staticLogFilePath;

    public DataBackupTool()
    {
        // 创建全局取消信号事件（用于跨进程通知自动备份终止）
        try
        {
            cancelEventHandle = new System.Threading.EventWaitHandle(false, System.Threading.EventResetMode.ManualReset, CancelEventName);
            cancelEventHandle.Reset();
        }
        catch { }
        
        InitializeComponent();
        LoadConfig();
        InitializeLogWatcher();
        
        // 在窗体完全加载后设置默认选中状态（解决时序问题）
        this.Shown += DataBackupTool_Shown;
    }
    
    // 窗体显示后设置默认选项
    private void DataBackupTool_Shown(object sender, EventArgs e)
    {
        // 强制设置选中状态（不管之前是什么状态）
        radioButton11.Checked = true;
        radioButton12.Checked = false;
        radioButton13.Checked = false;
    }
    
    private void InitializeComponent()
    {
        this.Text = "数据自动备份归档工具";
        this.ClientSize = new Size(822, 478);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.Font = new Font("微软雅黑", 9f);
        this.FormBorderStyle = FormBorderStyle.Sizable;
        this.AutoScaleMode = AutoScaleMode.Font;
        this.FormClosing += DataBackupTool_FormClosing;
        
        备份记录 = new TabControl();
        备份记录.Dock = DockStyle.Fill;
        备份记录.TabIndex = 2;
        备份记录.Font = new Font("微软雅黑", 10.5f, FontStyle.Bold);
        
        tabPage3 = new TabPage();
        tabPage3.Text = "备份设置";
        tabPage3.Location = new Point(4, 28);
        tabPage3.Size = new Size(814, 422);
        tabPage3.Padding = new Padding(3);
        tabPage3.BackColor = Color.Gainsboro;
        
        tabPage4 = new TabPage();
        tabPage4.Text = "操作记录";
        tabPage4.Location = new Point(4, 28);
        tabPage4.Size = new Size(814, 422);
        tabPage4.Padding = new Padding(3);
        tabPage4.BackColor = Color.Gainsboro;
        tabPage4.ForeColor = SystemColors.ControlText;
        
        dataGridView1 = new DataGridView();
        dataGridView1.Location = new Point(10, 12);
        dataGridView1.Size = new Size(794, 355);
        dataGridView1.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        dataGridView1.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        dataGridView1.RowHeadersVisible = false;
        dataGridView1.AllowUserToAddRows = false;
        dataGridView1.ReadOnly = true;
        dataGridView1.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        dataGridView1.BackgroundColor = Color.White;
        dataGridView1.BorderStyle = BorderStyle.Fixed3D;
        dataGridView1.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
        dataGridView1.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
        dataGridView1.ColumnHeadersHeight = 30;
        dataGridView1.Font = new Font("微软雅黑", 9f);
        dataGridView1.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(64, 64, 64);
        dataGridView1.ColumnHeadersDefaultCellStyle.ForeColor = Color.White;
        dataGridView1.ColumnHeadersDefaultCellStyle.Font = new Font("微软雅黑", 9.5f, FontStyle.Bold);
        dataGridView1.DefaultCellStyle.SelectionBackColor = Color.FromArgb(100, 149, 237);
        dataGridView1.DefaultCellStyle.SelectionForeColor = Color.White;
        dataGridView1.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(245, 245, 245);
        dataGridView1.CellContentClick += DataGridView1_CellContentClick;
        
        DataGridViewTextBoxColumn colGuid = new DataGridViewTextBoxColumn();
        colGuid.Name = "colGuid";
        colGuid.HeaderText = "批次GUID";
        colGuid.MinimumWidth = 120;
        
        DataGridViewTextBoxColumn colStatus = new DataGridViewTextBoxColumn();
        colStatus.Name = "colStatus";
        colStatus.HeaderText = "任务状态";
        colStatus.MinimumWidth = 80;
        
        DataGridViewTextBoxColumn colType = new DataGridViewTextBoxColumn();
        colType.Name = "colType";
        colType.HeaderText = "操作类型";
        colType.MinimumWidth = 80;
        
        DataGridViewTextBoxColumn colPath = new DataGridViewTextBoxColumn();
        colPath.Name = "colPath";
        colPath.HeaderText = "备份路径";
        colPath.MinimumWidth = 150;
        
        DataGridViewTextBoxColumn colRetry = new DataGridViewTextBoxColumn();
        colRetry.Name = "colRetry";
        colRetry.HeaderText = "重试";
        colRetry.MinimumWidth = 50;
        
        DataGridViewTextBoxColumn colStartTime = new DataGridViewTextBoxColumn();
        colStartTime.Name = "colStartTime";
        colStartTime.HeaderText = "批次开始时间";
        colStartTime.MinimumWidth = 120;
        
        DataGridViewTextBoxColumn colLog = new DataGridViewTextBoxColumn();
        colLog.Name = "colLog";
        colLog.HeaderText = "任务日志";
        colLog.MinimumWidth = 100;
        
        DataGridViewTextBoxColumn colCreateTime = new DataGridViewTextBoxColumn();
        colCreateTime.Name = "colCreateTime";
        colCreateTime.HeaderText = "任务创建时间";
        colCreateTime.MinimumWidth = 120;
        
        DataGridViewButtonColumn colAction = new DataGridViewButtonColumn();
        colAction.Name = "colAction";
        colAction.HeaderText = "操作";
        colAction.MinimumWidth = 80;
        colAction.Text = "查看详情";
        colAction.UseColumnTextForButtonValue = true;
        colAction.DefaultCellStyle.BackColor = Color.FromArgb(66, 139, 202);
        colAction.DefaultCellStyle.ForeColor = Color.White;
        
        dataGridView1.Columns.Add(colGuid);
        dataGridView1.Columns.Add(colStatus);
        dataGridView1.Columns.Add(colType);
        dataGridView1.Columns.Add(colPath);
        dataGridView1.Columns.Add(colRetry);
        dataGridView1.Columns.Add(colStartTime);
        dataGridView1.Columns.Add(colLog);
        dataGridView1.Columns.Add(colCreateTime);
        dataGridView1.Columns.Add(colAction);
        
        // 添加清空记录按钮
        buttonClearRecords = new Button();
        buttonClearRecords.Location = new Point(650, 375);
        buttonClearRecords.Size = new Size(150, 30);
        buttonClearRecords.Text = "清空操作记录";
        buttonClearRecords.BackColor = Color.Firebrick;
        buttonClearRecords.ForeColor = Color.White;
        buttonClearRecords.UseVisualStyleBackColor = false;
        buttonClearRecords.Font = new Font("微软雅黑", 10f, FontStyle.Bold);
        buttonClearRecords.Click += ButtonClearRecords_Click;
        
        tabPage4.Controls.Add(buttonClearRecords);  // 先添加按钮
        tabPage4.Controls.Add(dataGridView1);       // 后添加表格
        
        groupBox1 = new GroupBox();
        groupBox1.Location = new Point(5, 6);
        groupBox1.Size = new Size(786, 68);
        groupBox1.Text = "手动备份/导入";
        
        label1 = new Label();
        label1.AutoSize = true;
        label1.Location = new Point(12, 25);
        label1.Text = "输入GUID";
        label1.ForeColor = SystemColors.ControlDarkDark;
        
        textBox1 = new TextBox();
        textBox1.Location = new Point(93, 22);
        textBox1.Size = new Size(427, 26);
        textBox1.TextChanged += TextBox1_TextChanged;
        textBox1.KeyPress += TextBox1_KeyPress;
        
        comboBox1 = new ComboBox();
        comboBox1.Location = new Point(547, 22);
        comboBox1.Size = new Size(75, 27);
        comboBox1.Items.Add("立即备份");
        comboBox1.Items.Add("立即导入");
        comboBox1.SelectedIndex = 0;
        
        button1 = new Button();
        button1.Location = new Point(640, 22);
        button1.Size = new Size(61, 28);
        button1.Text = "执行";
        button1.BackColor = Color.MediumAquamarine;
        button1.UseVisualStyleBackColor = false;
        button1.Click += Button1_Click;
        button1.Enabled = false;
        
        button2 = new Button();
        button2.Location = new Point(718, 21);
        button2.Size = new Size(61, 29);
        button2.Text = "取消";
        button2.BackColor = Color.IndianRed;
        button2.UseVisualStyleBackColor = false;
        button2.Click += Button2_Click;
        
        panel1 = new Panel();
        panel1.Location = new Point(16, 54);
        panel1.Size = new Size(11, 11);
        panel1.BackColor = Color.LawnGreen;
        panel1.BorderStyle = BorderStyle.FixedSingle;
        
        label2 = new Label();
        label2.AutoSize = true;
        label2.Location = new Point(28, 49);
        label2.Text = "系统就绪";
        
        groupBox1.Controls.Add(label1);
        groupBox1.Controls.Add(textBox1);
        groupBox1.Controls.Add(comboBox1);
        groupBox1.Controls.Add(button1);
        groupBox1.Controls.Add(button2);
        groupBox1.Controls.Add(panel1);
        groupBox1.Controls.Add(label2);
        
        tabControl1 = new TabControl();
        tabControl1.Location = new Point(0, 84);
        tabControl1.Size = new Size(812, 233);
        
        tabPage1 = new TabPage();
        tabPage1.Text = "自动备份";
        
        label3 = new Label();
        label3.AutoSize = true;
        label3.Location = new Point(13, 13);
        label3.Text = "执行时间";
        label3.BackColor = Color.LightGray;
        
        dateTimePicker1 = new DateTimePicker();
        dateTimePicker1.Location = new Point(17, 39);
        dateTimePicker1.Size = new Size(86, 26);
        dateTimePicker1.Format = DateTimePickerFormat.Time;
        dateTimePicker1.ShowUpDown = true;
        dateTimePicker1.ValueChanged += DateTimePicker1_ValueChanged;
        
        label4 = new Label();
        label4.AutoSize = true;
        label4.Location = new Point(13, 107);
        label4.Text = "备份根目录";
        label4.BackColor = Color.LightGray;
        
        textBox3 = new TextBox();
        textBox3.Location = new Point(17, 138);
        textBox3.Size = new Size(188, 26);
        textBox3.TextChanged += TextBox3_TextChanged;
        
        button3 = new Button();
        button3.Location = new Point(211, 138);
        button3.Size = new Size(53, 26);
        button3.Text = "浏览";
        button3.Click += Button3_Click;
        
        label5 = new Label();
        label5.AutoSize = true;
        label5.Location = new Point(356, 13);
        label5.Text = "备份内容";
        label5.BackColor = Color.LightGray;
        
        Panel panelBackupContent = new Panel();
        panelBackupContent.Location = new Point(360, 35);
        panelBackupContent.Size = new Size(180, 110);
        panelBackupContent.BackColor = Color.Transparent;
        
        radioButton1 = new RadioButton();
        radioButton1.AutoSize = true;
        radioButton1.Location = new Point(4, 7);
        radioButton1.Text = "仅图片";
        radioButton1.CheckedChanged += BackupContent_CheckedChanged;
        
        radioButton2 = new RadioButton();
        radioButton2.AutoSize = true;
        radioButton2.Location = new Point(4, 49);
        radioButton2.Text = "仅数据";
        radioButton2.CheckedChanged += BackupContent_CheckedChanged;
        
        radioButton3 = new RadioButton();
        radioButton3.AutoSize = true;
        radioButton3.Location = new Point(4, 90);
        radioButton3.Text = "图片+数据";
        radioButton3.Checked = true;
        radioButton3.CheckedChanged += BackupContent_CheckedChanged;
        
        panelBackupContent.Controls.Add(radioButton1);
        panelBackupContent.Controls.Add(radioButton2);
        panelBackupContent.Controls.Add(radioButton3);
        
        label6 = new Label();
        label6.AutoSize = true;
        label6.Location = new Point(570, 13);
        label6.Text = "备份后删除";
        label6.BackColor = Color.LightGray;
        
        Panel panelDeleteOption = new Panel();
        panelDeleteOption.Location = new Point(562, 35);
        panelDeleteOption.Size = new Size(100, 80);
        panelDeleteOption.BackColor = Color.Transparent;
        
        radioButton5 = new RadioButton();
        radioButton5.AutoSize = true;
        radioButton5.Location = new Point(4, 8);
        radioButton5.Text = "删除数据";
        radioButton5.CheckedChanged += DeleteOption_CheckedChanged;
        
        radioButton6 = new RadioButton();
        radioButton6.AutoSize = true;
        radioButton6.Location = new Point(4, 49);
        radioButton6.Text = "暂不删除";
        radioButton6.Checked = true;
        radioButton6.CheckedChanged += DeleteOption_CheckedChanged;
        
        panelDeleteOption.Controls.Add(radioButton5);
        panelDeleteOption.Controls.Add(radioButton6);
        
        checkBox1 = new CheckBox();
        checkBox1.AutoSize = true;
        checkBox1.Font = new Font("微软雅黑", 12f, FontStyle.Bold);
        checkBox1.Location = new Point(530, 154);
        checkBox1.Text = "未启用";
        checkBox1.Checked = false;
        checkBox1.BackColor = Color.Transparent;
        checkBox1.ForeColor = Color.Red;
        checkBox1.UseVisualStyleBackColor = true;
        checkBox1.CheckedChanged += checkBox1_CheckedChanged;
        
        // 撤销备份按钮
        Button buttonCancelBackup = new Button();
        buttonCancelBackup.Location = new Point(620, 150);
        buttonCancelBackup.Size = new Size(80, 35);
        buttonCancelBackup.Text = "撤销备份";
        buttonCancelBackup.BackColor = Color.IndianRed;
        buttonCancelBackup.ForeColor = Color.White;
        buttonCancelBackup.UseVisualStyleBackColor = false;
        buttonCancelBackup.Click += ButtonCancelBackup_Click;
        
        button5 = new Button();
        button5.Location = new Point(710, 147);
        button5.Size = new Size(76, 39);
        button5.Text = "保存配置";
        button5.BackColor = Color.SandyBrown;
        button5.UseVisualStyleBackColor = false;
        button5.Click += Button5_Click;
        
        tabPage1.Controls.Add(label3);
        tabPage1.Controls.Add(dateTimePicker1);
        tabPage1.Controls.Add(label4);
        tabPage1.Controls.Add(textBox3);
        tabPage1.Controls.Add(button3);
        tabPage1.Controls.Add(label5);
        tabPage1.Controls.Add(panelBackupContent);
        tabPage1.Controls.Add(label6);
        tabPage1.Controls.Add(panelDeleteOption);
        tabPage1.Controls.Add(checkBox1);
        tabPage1.Controls.Add(buttonCancelBackup);
        tabPage1.Controls.Add(button5);
        
        tabPage2 = new TabPage();
        tabPage2.Text = "一键导入";
        
        button6 = new Button();
        button6.Location = new Point(218, 116);
        button6.Size = new Size(8, 8);
        button6.Visible = false;
        
        label8 = new Label();
        label8.AutoSize = true;
        label8.Location = new Point(266, 18);
        label8.Text = "导入选择处理";
        label8.BackColor = Color.LightGray;
        
        panelDuplicateOption = new Panel();
        panelDuplicateOption.Location = new Point(263, 42);
        panelDuplicateOption.Size = new Size(180, 90);
        panelDuplicateOption.BackColor = Color.Transparent;
        
        radioButton11 = new RadioButton();
        radioButton11.AutoSize = true;
        radioButton11.Location = new Point(0, 7);
        radioButton11.Text = "追加导入";
        
        radioButton12 = new RadioButton();
        radioButton12.AutoSize = true;
        radioButton12.Location = new Point(0, 39);
        radioButton12.Text = "覆盖重复";
        
        radioButton13 = new RadioButton();
        radioButton13.AutoSize = true;
        radioButton13.Location = new Point(0, 71);
        radioButton13.Text = "清空后导入";
        
        // 添加到容器（同一个Panel中的RadioButton会自动互斥）
        panelDuplicateOption.Controls.Add(radioButton11);
        panelDuplicateOption.Controls.Add(radioButton12);
        panelDuplicateOption.Controls.Add(radioButton13);
        
        // 设置初始值（不需要手动设置其他按钮为false，WinForms会自动处理互斥）
        radioButton11.Checked = true;
        
        label9 = new Label();
        label9.AutoSize = true;
        label9.Location = new Point(568, 18);
        label9.Text = "导入后操作";
        label9.BackColor = Color.LightGray;
        
        Panel panelAfterImport = new Panel();
        panelAfterImport.Location = new Point(558, 42);
        panelAfterImport.Size = new Size(180, 70);
        panelAfterImport.BackColor = Color.Transparent;
        
        radioButton14 = new RadioButton();
        radioButton14.AutoSize = true;
        radioButton14.Location = new Point(0, 7);
        radioButton14.Text = "保留备份文件";
        radioButton14.Checked = true;
        radioButton14.CheckedChanged += AfterImport_CheckedChanged;
        
        radioButton15 = new RadioButton();
        radioButton15.AutoSize = true;
        radioButton15.Location = new Point(0, 47);
        radioButton15.Text = "删除备份文件";
        radioButton15.CheckedChanged += AfterImport_CheckedChanged;
        
        panelAfterImport.Controls.Add(radioButton14);
        panelAfterImport.Controls.Add(radioButton15);
        
        label10 = new Label();
        label10.AutoSize = true;
        label10.Location = new Point(13, 156);
        label10.Text = "导入源目录";
        label10.BackColor = Color.LightGray;
        
        textBox4 = new TextBox();
        textBox4.Location = new Point(115, 156);
        textBox4.Size = new Size(271, 26);
        textBox4.TextChanged += TextBox4_TextChanged;
        
        button7 = new Button();
        button7.Location = new Point(392, 156);
        button7.Size = new Size(53, 26);
        button7.Text = "浏览";
        button7.Click += Button7_Click;
        
        button9 = new Button();
        button9.Location = new Point(620, 150);
        button9.Size = new Size(80, 35);
        button9.Text = "一键导入";
        button9.BackColor = Color.LimeGreen;
        button9.UseVisualStyleBackColor = false;
        button9.Click += Button9_Click;
        
        // 一键导入标签页的保存配置按钮
        Button buttonSaveImportConfig = new Button();
        buttonSaveImportConfig.Location = new Point(710, 147);
        buttonSaveImportConfig.Size = new Size(76, 39);
        buttonSaveImportConfig.Text = "保存配置";
        buttonSaveImportConfig.BackColor = Color.SandyBrown;
        buttonSaveImportConfig.UseVisualStyleBackColor = false;
        buttonSaveImportConfig.Visible = true;
        buttonSaveImportConfig.Click += ButtonSaveImportConfig_Click;
        
        tabPage2.Controls.Add(button6);
        tabPage2.Controls.Add(label8);
        tabPage2.Controls.Add(panelDuplicateOption);
        tabPage2.Controls.Add(label9);
        tabPage2.Controls.Add(panelAfterImport);
        tabPage2.Controls.Add(label10);
        tabPage2.Controls.Add(textBox4);
        tabPage2.Controls.Add(button7);
        tabPage2.Controls.Add(button9);
        tabPage2.Controls.Add(buttonSaveImportConfig);
        
        tabControl1.TabPages.Add(tabPage1);
        tabControl1.TabPages.Add(tabPage2);
        
        // 创建数据库配置标签页
        tabPageDbConfig = new TabPage();
        tabPageDbConfig.Text = "数据库配置";
        tabPageDbConfig.BackColor = Color.Gainsboro;
        
        // === 左侧：备份数据库配置 ===
        Label labelBackupTitle = new Label();
        labelBackupTitle.AutoSize = true;
        labelBackupTitle.Location = new Point(20, 5);
        labelBackupTitle.Text = "备份数据库配置";
        labelBackupTitle.Font = new Font("微软雅黑", 11f, FontStyle.Bold);
        labelBackupTitle.BackColor = Color.Transparent;
        
        // 数据库主机
        labelBackupDbHost = new Label();
        labelBackupDbHost.AutoSize = true;
        labelBackupDbHost.Location = new Point(20, 30);
        labelBackupDbHost.Text = "数据库主机";
        labelBackupDbHost.BackColor = Color.LightGray;
        
        textBoxBackupDbHost = new TextBox();
        textBoxBackupDbHost.Location = new Point(20, 55);
        textBoxBackupDbHost.Size = new Size(150, 26);
        textBoxBackupDbHost.Text = "127.0.0.1";
        
        // 数据库端口
        labelBackupDbPort = new Label();
        labelBackupDbPort.AutoSize = true;
        labelBackupDbPort.Location = new Point(190, 30);
        labelBackupDbPort.Text = "端口";
        labelBackupDbPort.BackColor = Color.LightGray;
        
        textBoxBackupDbPort = new TextBox();
        textBoxBackupDbPort.Location = new Point(190, 55);
        textBoxBackupDbPort.Size = new Size(70, 26);
        textBoxBackupDbPort.Text = "3306";
        
        // 数据库用户名
        labelBackupDbUser = new Label();
        labelBackupDbUser.AutoSize = true;
        labelBackupDbUser.Location = new Point(280, 30);
        labelBackupDbUser.Text = "用户名";
        labelBackupDbUser.BackColor = Color.LightGray;
        
        textBoxBackupDbUser = new TextBox();
        textBoxBackupDbUser.Location = new Point(280, 55);
        textBoxBackupDbUser.Size = new Size(100, 26);
        textBoxBackupDbUser.Text = "root";
        
        // 数据库密码
        labelBackupDbPassword = new Label();
        labelBackupDbPassword.AutoSize = true;
        labelBackupDbPassword.Location = new Point(20, 90);
        labelBackupDbPassword.Text = "密码";
        labelBackupDbPassword.BackColor = Color.LightGray;
        
        textBoxBackupDbPassword = new TextBox();
        textBoxBackupDbPassword.Location = new Point(20, 115);
        textBoxBackupDbPassword.Size = new Size(150, 26);
        textBoxBackupDbPassword.PasswordChar = '*';
        
        // 数据库名称
        labelBackupDbName = new Label();
        labelBackupDbName.AutoSize = true;
        labelBackupDbName.Location = new Point(190, 90);
        labelBackupDbName.Text = "数据库名";
        labelBackupDbName.BackColor = Color.LightGray;
        
        textBoxBackupDbName = new TextBox();
        textBoxBackupDbName.Location = new Point(190, 115);
        textBoxBackupDbName.Size = new Size(190, 26);
        
        // 连接状态标签
        labelBackupConnectionStatus = new Label();
        labelBackupConnectionStatus.AutoSize = true;
        labelBackupConnectionStatus.Location = new Point(20, 155);
        labelBackupConnectionStatus.Size = new Size(360, 30);
        labelBackupConnectionStatus.Text = "";
        labelBackupConnectionStatus.Font = new Font("微软雅黑", 10f, FontStyle.Bold);
        
        // 测试连接按钮
        buttonTestBackupConnection = new Button();
        buttonTestBackupConnection.Location = new Point(60, 165);
        buttonTestBackupConnection.Size = new Size(100, 30);
        buttonTestBackupConnection.Text = "测试连接";
        buttonTestBackupConnection.BackColor = Color.LightBlue;
        buttonTestBackupConnection.UseVisualStyleBackColor = false;
        buttonTestBackupConnection.Click += ButtonTestBackupConnection_Click;
        
        // 保存配置按钮
        buttonSaveBackupDbConfig = new Button();
        buttonSaveBackupDbConfig.Location = new Point(180, 165);
        buttonSaveBackupDbConfig.Size = new Size(100, 30);
        buttonSaveBackupDbConfig.Text = "保存配置";
        buttonSaveBackupDbConfig.BackColor = Color.SandyBrown;
        buttonSaveBackupDbConfig.UseVisualStyleBackColor = false;
        buttonSaveBackupDbConfig.Click += ButtonSaveBackupDbConfig_Click;
        
        // === 右侧分隔线 ===
        Label separatorLine = new Label();
        separatorLine.Location = new Point(405, 5);
        separatorLine.Size = new Size(2, 200);
        separatorLine.BackColor = Color.DarkGray;
        
        // === 右侧：导入数据库配置 ===
        Label labelImportTitle = new Label();
        labelImportTitle.AutoSize = true;
        labelImportTitle.Location = new Point(430, 5);
        labelImportTitle.Text = "导入数据库配置";
        labelImportTitle.Font = new Font("微软雅黑", 11f, FontStyle.Bold);
        labelImportTitle.BackColor = Color.Transparent;
        
        // 数据库主机
        labelImportDbHost = new Label();
        labelImportDbHost.AutoSize = true;
        labelImportDbHost.Location = new Point(430, 30);
        labelImportDbHost.Text = "数据库主机";
        labelImportDbHost.BackColor = Color.LightGray;
        
        textBoxImportDbHost = new TextBox();
        textBoxImportDbHost.Location = new Point(430, 55);
        textBoxImportDbHost.Size = new Size(150, 26);
        textBoxImportDbHost.Text = "127.0.0.1";
        
        // 数据库端口
        labelImportDbPort = new Label();
        labelImportDbPort.AutoSize = true;
        labelImportDbPort.Location = new Point(600, 30);
        labelImportDbPort.Text = "端口";
        labelImportDbPort.BackColor = Color.LightGray;
        
        textBoxImportDbPort = new TextBox();
        textBoxImportDbPort.Location = new Point(600, 55);
        textBoxImportDbPort.Size = new Size(70, 26);
        textBoxImportDbPort.Text = "3306";
        
        // 数据库用户名
        labelImportDbUser = new Label();
        labelImportDbUser.AutoSize = true;
        labelImportDbUser.Location = new Point(690, 30);
        labelImportDbUser.Text = "用户名";
        labelImportDbUser.BackColor = Color.LightGray;
        
        textBoxImportDbUser = new TextBox();
        textBoxImportDbUser.Location = new Point(690, 55);
        textBoxImportDbUser.Size = new Size(100, 26);
        textBoxImportDbUser.Text = "root";
        
        // 数据库密码
        labelImportDbPassword = new Label();
        labelImportDbPassword.AutoSize = true;
        labelImportDbPassword.Location = new Point(430, 90);
        labelImportDbPassword.Text = "密码";
        labelImportDbPassword.BackColor = Color.LightGray;
        
        textBoxImportDbPassword = new TextBox();
        textBoxImportDbPassword.Location = new Point(430, 115);
        textBoxImportDbPassword.Size = new Size(150, 26);
        textBoxImportDbPassword.PasswordChar = '*';
        
        // 数据库名称
        labelImportDbName = new Label();
        labelImportDbName.AutoSize = true;
        labelImportDbName.Location = new Point(600, 90);
        labelImportDbName.Text = "数据库名";
        labelImportDbName.BackColor = Color.LightGray;
        
        textBoxImportDbName = new TextBox();
        textBoxImportDbName.Location = new Point(600, 115);
        textBoxImportDbName.Size = new Size(190, 26);
        
        // 连接状态标签
        labelImportConnectionStatus = new Label();
        labelImportConnectionStatus.AutoSize = true;
        labelImportConnectionStatus.Location = new Point(430, 155);
        labelImportConnectionStatus.Size = new Size(360, 30);
        labelImportConnectionStatus.Text = "";
        labelImportConnectionStatus.Font = new Font("微软雅黑", 10f, FontStyle.Bold);
        
        // 测试连接按钮
        buttonTestImportConnection = new Button();
        buttonTestImportConnection.Location = new Point(470, 165);
        buttonTestImportConnection.Size = new Size(100, 30);
        buttonTestImportConnection.Text = "测试连接";
        buttonTestImportConnection.BackColor = Color.LightBlue;
        buttonTestImportConnection.UseVisualStyleBackColor = false;
        buttonTestImportConnection.Click += ButtonTestImportConnection_Click;
        
        // 保存配置按钮
        buttonSaveImportDbConfig = new Button();
        buttonSaveImportDbConfig.Location = new Point(590, 165);
        buttonSaveImportDbConfig.Size = new Size(100, 30);
        buttonSaveImportDbConfig.Text = "保存配置";
        buttonSaveImportDbConfig.BackColor = Color.SandyBrown;
        buttonSaveImportDbConfig.UseVisualStyleBackColor = false;
        buttonSaveImportDbConfig.Click += ButtonSaveImportDbConfig_Click;
        
        // 添加所有控件到标签页
        tabPageDbConfig.Controls.Add(labelBackupTitle);
        tabPageDbConfig.Controls.Add(labelBackupDbHost);
        tabPageDbConfig.Controls.Add(textBoxBackupDbHost);
        tabPageDbConfig.Controls.Add(labelBackupDbPort);
        tabPageDbConfig.Controls.Add(textBoxBackupDbPort);
        tabPageDbConfig.Controls.Add(labelBackupDbUser);
        tabPageDbConfig.Controls.Add(textBoxBackupDbUser);
        tabPageDbConfig.Controls.Add(labelBackupDbPassword);
        tabPageDbConfig.Controls.Add(textBoxBackupDbPassword);
        tabPageDbConfig.Controls.Add(labelBackupDbName);
        tabPageDbConfig.Controls.Add(textBoxBackupDbName);
        tabPageDbConfig.Controls.Add(labelBackupConnectionStatus);
        tabPageDbConfig.Controls.Add(buttonTestBackupConnection);
        tabPageDbConfig.Controls.Add(buttonSaveBackupDbConfig);
        
        tabPageDbConfig.Controls.Add(separatorLine);
        
        tabPageDbConfig.Controls.Add(labelImportTitle);
        tabPageDbConfig.Controls.Add(labelImportDbHost);
        tabPageDbConfig.Controls.Add(textBoxImportDbHost);
        tabPageDbConfig.Controls.Add(labelImportDbPort);
        tabPageDbConfig.Controls.Add(textBoxImportDbPort);
        tabPageDbConfig.Controls.Add(labelImportDbUser);
        tabPageDbConfig.Controls.Add(textBoxImportDbUser);
        tabPageDbConfig.Controls.Add(labelImportDbPassword);
        tabPageDbConfig.Controls.Add(textBoxImportDbPassword);
        tabPageDbConfig.Controls.Add(labelImportDbName);
        tabPageDbConfig.Controls.Add(textBoxImportDbName);
        tabPageDbConfig.Controls.Add(labelImportConnectionStatus);
        tabPageDbConfig.Controls.Add(buttonTestImportConnection);
        tabPageDbConfig.Controls.Add(buttonSaveImportDbConfig);
        
        tabControl1.TabPages.Add(tabPageDbConfig);
        
        groupBox2 = new GroupBox();
        groupBox2.Location = new Point(3, 317);
        groupBox2.Size = new Size(810, 104);
        groupBox2.Text = "实时运行日志";
        
        button4 = new Button();
        button4.Location = new Point(727, 0);
        button4.Size = new Size(75, 26);
        button4.Text = "清空日志";
        button4.Click += Button4_Click;
        
        textBox2 = new TextBox();
        textBox2.Location = new Point(-3, 25);
        textBox2.Size = new Size(816, 79);
        textBox2.Multiline = true;
        textBox2.ReadOnly = true;
        textBox2.ScrollBars = ScrollBars.Vertical;
        textBox2.Font = new Font("Consolas", 8.25f);
        textBox2.BackColor = Color.Black;
        textBox2.ForeColor = Color.White;
        
        groupBox2.Controls.Add(button4);
        groupBox2.Controls.Add(textBox2);
        
        tabPage3.Controls.Add(groupBox1);
        tabPage3.Controls.Add(tabControl1);
        tabPage3.Controls.Add(groupBox2);
        
        备份记录.TabPages.Add(tabPage3);
        备份记录.TabPages.Add(tabPage4);
        
        this.Controls.Add(备份记录);
        
        InitializeControlScaling();
        
        LoadOperationRecords();
        
        // 在窗体加载时确保按钮可见
        this.Load += (s, e) => {
            buttonClearRecords.Visible = true;
            buttonClearRecords.BringToFront();
        };
        
        Log("程序启动成功，等待操作...");
    }
    
    private Dictionary<Control, Rectangle> originalControlBounds = new Dictionary<Control, Rectangle>();
    private int originalWidth = 822;
    private int originalHeight = 478;
    
    private void InitializeControlScaling()
    {
        foreach (Control ctrl in GetAllControls(this))
        {
            originalControlBounds[ctrl] = new Rectangle(ctrl.Location, ctrl.Size);
        }
        
        this.Resize += new EventHandler(Form_Resize);
    }
    
    private List<Control> GetAllControls(Control container)
    {
        List<Control> controls = new List<Control>();
        foreach (Control ctrl in container.Controls)
        {
            controls.Add(ctrl);
            controls.AddRange(GetAllControls(ctrl));
        }
        return controls;
    }
    
    private void Form_Resize(object sender, EventArgs e)
    {
        float scaleX = (float)this.ClientSize.Width / originalWidth;
        float scaleY = (float)this.ClientSize.Height / originalHeight;
        
        foreach (Control ctrl in originalControlBounds.Keys)
        {
            Rectangle original = originalControlBounds[ctrl];
            ctrl.Location = new Point(
                (int)(original.X * scaleX),
                (int)(original.Y * scaleY)
            );
            ctrl.Size = new Size(
                (int)(original.Width * scaleX),
                (int)(original.Height * scaleY)
            );
        }
    }
    
    // 记录日志到文件（UI更新由FileSystemWatcher负责）
    private void Log(string message)
    {
        string logLine = "[" + DateTime.Now.ToString("HH:mm:ss") + "] " + message;
        
        // 只写入日志文件，UI 更新由 FileSystemWatcher 负责
        if (!string.IsNullOrEmpty(logFilePath))
        {
            try
            {
                // 使用带 BOM 的 UTF-8 编码，避免中文乱码
                var utf8WithBom = new System.Text.UTF8Encoding(true);
                System.IO.File.AppendAllText(logFilePath, logLine + Environment.NewLine, utf8WithBom);
            }
            catch
            {
                // 忽略日志写入错误
            }
        }
    }
    
    // 初始化日志文件监控，实时更新文本框
    private void InitializeLogWatcher()
    {
        // 使用程序所在目录，确保与定时任务写入的路径一致
        string exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
        string exeDir = Path.GetDirectoryName(exePath);
        logFilePath = Path.Combine(exeDir, "backup_log.txt");
        staticLogFilePath = logFilePath;
        
        if (!File.Exists(logFilePath))
        {
            File.Create(logFilePath).Close();
        }
        
        // 如果已有旧的监视器，先清理
        if (logWatcher != null)
        {
            logWatcher.EnableRaisingEvents = false;
            logWatcher.Changed -= LogFile_Changed;
            logWatcher.Dispose();
            logWatcher = null;
        }
        
        // 初始化文件系统监视器，监控日志文件变化
        logWatcher = new FileSystemWatcher();
        logWatcher.InternalBufferSize = 65536;
        logWatcher.Path = Path.GetDirectoryName(logFilePath);
        logWatcher.Filter = Path.GetFileName(logFilePath);
        logWatcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size;
        logWatcher.Changed += LogFile_Changed;
        logWatcher.EnableRaisingEvents = true;
        
        lastFileSize = new FileInfo(logFilePath).Length;
    }
    
    // 处理日志文件变化事件，实时更新文本框
    private void LogFile_Changed(object sender, FileSystemEventArgs e)
    {
        try
        {
            FileInfo fileInfo = new FileInfo(logFilePath);
            long currentSize = fileInfo.Length;
            
            // 调试信息
            System.Diagnostics.Debug.WriteLine("[LogWatcher] Event triggered: {0}, CurrentSize: {1}, LastSize: {2}", e.ChangeType, currentSize, lastFileSize);
            
            if (currentSize > lastFileSize)
            {
                using (FileStream stream = new FileStream(logFilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    stream.Seek(lastFileSize, SeekOrigin.Begin);
                    using (StreamReader reader = new StreamReader(stream))
                    {
                        string newContent = reader.ReadToEnd();
                        if (!string.IsNullOrEmpty(newContent))
                        {
                            this.Invoke((MethodInvoker)delegate {
                                textBox2.AppendText(newContent);
                                textBox2.ScrollToCaret();
                            });
                        }
                    }
                }
                lastFileSize = currentSize;
            }
            else if (currentSize == 0)
            {
                // 文件被清空，重置计数器
                lastFileSize = 0;
                System.Diagnostics.Debug.WriteLine("[LogWatcher] File cleared, resetting lastFileSize to 0");
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("[LogWatcher Error] {0}", ex.Message);
        }
    }
    
    // 更新状态栏显示
    private void UpdateStatus(string status, Color color)
    {
        label2.Text = status;
        panel1.BackColor = color;
    }
    
    // 验证GUID格式是否有效
    private bool IsValidGuid(string guid)
    {
        guid = guid.Replace("-", "").Trim();
        if (guid.Length != 32) return false;
        foreach (char c in guid)
        {
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            {
                return false;
            }
        }
        return true;
    }
    
    private string GetSelectedBackupContent()
    {
        if (radioButton1.Checked) return "仅图片";
        if (radioButton2.Checked) return "仅数据";
        return "图片+数据";
    }
    
    private string GetSelectedDeleteOption()
    {
        if (radioButton5.Checked) return "删除数据";
        return "暂不删除";
    }
    
    // 默认导入图片+数据
    private string GetSelectedImportContent()
    {
        return "图片+数据";
    }
    
    private string GetSelectedDuplicateOption()
    {
        if (radioButton11.Checked) return "追加导入";
        if (radioButton12.Checked) return "覆盖重复";
        return "清空后导入";
    }
    
    private string GetSelectedAfterImport()
    {
        if (radioButton15.Checked) return "删除备份文件";
        return "保留备份文件";
    }
    
    // GUID输入框内容变化时更新备份按钮状态
    private void TextBox1_TextChanged(object sender, EventArgs e)
    {
        string guid = textBox1.Text.Trim();
        button1.Enabled = IsValidGuid(guid);
    }
    
    // GUID输入框回车键快捷触发备份
    private void TextBox1_KeyPress(object sender, KeyPressEventArgs e)
    {
        if (e.KeyChar == (char)Keys.Enter && button1.Enabled)
        {
            Button1_Click(sender, e);
        }
    }
    
    // 备份路径输入框内容变化处理
    private void TextBox3_TextChanged(object sender, EventArgs e)
    {
        string path = textBox3.Text.Trim();
        if (!string.IsNullOrEmpty(path))
        {
            bool isValid = Directory.Exists(path);
            if (!isValid)
            {
                Log("警告: 备份根目录路径无效");
            }
        }
    }
    
    // 导入路径输入框内容变化时更新导入按钮状态
    private void TextBox4_TextChanged(object sender, EventArgs e)
    {
        string path = textBox4.Text.Trim();
        button9.Enabled = !string.IsNullOrEmpty(path) && Directory.Exists(path);
    }
    
    // 时间选择器值变化处理
    private void DateTimePicker1_ValueChanged(object sender, EventArgs e)
    {
        Log("执行时间已更改为: " + dateTimePicker1.Value.ToShortTimeString());
    }
    
    // 备份内容单选框选择变化处理
    private void BackupContent_CheckedChanged(object sender, EventArgs e)
    {
        RadioButton rb = sender as RadioButton;
        if (rb != null && rb.Checked)
        {
            Log("备份内容已选择: " + rb.Text);
        }
    }
    
    // 备份后删除选项单选框选择变化处理
    private void DeleteOption_CheckedChanged(object sender, EventArgs e)
    {
        RadioButton rb = sender as RadioButton;
        if (rb != null && rb.Checked)
        {
            RadioButton[] options = { radioButton5, radioButton6 };
            foreach (RadioButton opt in options)
            {
                if (opt != rb) opt.Checked = false;
            }
            Log("备份后删除选项已选择: " + rb.Text);
        }
    }
    

    
    // 导入后操作选项单选框选择变化处理
    private void AfterImport_CheckedChanged(object sender, EventArgs e)
    {
        RadioButton rb = sender as RadioButton;
        if (rb != null && rb.Checked)
        {
            RadioButton[] options = { radioButton14, radioButton15 };
            foreach (RadioButton opt in options)
            {
                if (opt != rb) opt.Checked = false;
            }
            Log("导入后操作已选择: " + rb.Text);
        }
    }
    
    private void Button1_Click(object sender, EventArgs e)
    {
        string guid = textBox1.Text.Trim().Replace("-", "").ToLower();
        if (comboBox1.SelectedItem == null)
        {
            MessageBox.Show("请选择操作类型");
            return;
        }
        string action = comboBox1.SelectedItem.ToString();
        
        if (!IsValidGuid(guid))
        {
            MessageBox.Show("无效的GUID格式");
            return;
        }
        
        if (isWorking)
        {
            MessageBox.Show("正在执行操作，请等待完成");
            return;
        }
        
        isWorking = true;
        button1.Enabled = false;
        textBox1.Enabled = false;
        comboBox1.Enabled = false;
        
        if (action == "立即备份")
        {
            UpdateStatus("正在备份...", Color.Blue);
            Log("开始立即备份，GUID: " + guid + "，备份内容: " + GetSelectedBackupContent() + "，备份后删除: " + GetSelectedDeleteOption());
            
            ThreadPool.QueueUserWorkItem((state) =>
            {
                ExecuteBackup(guid);
            });
        }
        else
        {
            UpdateStatus("正在导入...", Color.Blue);
            Log("开始立即导入，GUID: " + guid);
            
            ThreadPool.QueueUserWorkItem((state) =>
            {
                ExecuteImport(guid);
            });
        }
    }
    
    private void Button2_Click(object sender, EventArgs e)
    {
        // 无论是否正在工作，都尝试终止所有相关进程
        DialogResult result = MessageBox.Show("确定要强制取消所有备份操作吗？", "确认中断", MessageBoxButtons.OKCancel);
        if (result == DialogResult.OK)
        {
            isWorking = false;
            
            // 发送跨进程取消信号
            if (cancelEventHandle != null)
            {
                try { cancelEventHandle.Set(); } catch { }
            }
            
            // 终止主进程
            System.Diagnostics.Process procToKill;
            lock (stateLock)
            {
                procToKill = currentProcess;
            }
            if (procToKill != null && !procToKill.HasExited)
            {
                try
                {
                    procToKill.Kill();
                    Log("主进程已被终止");
                }
                catch (Exception ex)
                {
                    Log("终止主进程时发生错误: " + ex.Message);
                }
                finally
                {
                    lock (stateLock)
                    {
                        currentProcess = null;
                    }
                }
            }
            
            // 终止所有相关的备份进程
            TerminateAllBackupProcesses();
            
            // 释放互斥锁
            if (backupMutex != null)
            {
                try
                {
                    backupMutex.ReleaseMutex();
                    Log("互斥锁已释放");
                }
                catch { }
                backupMutex = null;
            }
            
            UpdateStatus("操作已中断", Color.Red);
            Log("操作已被用户中断");
            ResetUI();
        }
    }
    
    // 终止本程序启动的备份相关进程（仅杀自己的子进程，不影响系统其他进程）
    private void TerminateAllBackupProcesses()
    {
        try
        {
            // ===== 终止本程序启动的 PowerShell 子进程（通过 PID 精确匹配）=====
            List<int> pidsToKill;
            lock (pidLock)
            {
                pidsToKill = new List<int>(childProcessPids);
            }
            
            foreach (int pid in pidsToKill)
            {
                try
                {
                    System.Diagnostics.Process proc = System.Diagnostics.Process.GetProcessById(pid);
                    if (proc != null && !proc.HasExited)
                    {
                        proc.Kill();
                        proc.WaitForExit(3000);
                        Log(String.Format("终止 PowerShell 子进程: {0}", pid));
                    }
                }
                catch (ArgumentException)
                {
                    // 进程已自然退出，忽略
                }
                catch (Exception ex)
                {
                    Log(String.Format("终止子进程 {0} 失败: {1}", pid, ex.Message));
                }
            }
            
            lock (pidLock)
            {
                childProcessPids.Clear();
            }
            
            // ===== 按名称终止本程序关联的 PowerShell 进程（覆盖跨进程场景）=====
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
            foreach (var process in System.Diagnostics.Process.GetProcessesByName("powershell"))
            {
                try
                {
                    // 通过命令行参数判断是否为本程序启动的 PowerShell 进程
                    if (process.StartInfo != null && !string.IsNullOrEmpty(process.StartInfo.Arguments))
                    {
                        if (process.StartInfo.Arguments.Contains("AutoBackup") ||
                            process.StartInfo.Arguments.Contains("GUID-Data") ||
                            process.StartInfo.Arguments.Contains("imagecopy") ||
                            process.StartInfo.Arguments.Contains("schema.ps1") ||
                            process.StartInfo.Arguments.Contains("DeleteData") ||
                            process.StartInfo.Arguments.Contains("ImportWorker"))
                        {
                            process.Kill();
                            Log(String.Format("终止关联 PowerShell 进程: {0}", process.Id));
                        }
                    }
                }
                catch { }
            }
            
            // ===== 终止 PowerShell 间接启动的 robocopy 子进程 =====
            foreach (var process in System.Diagnostics.Process.GetProcessesByName("robocopy"))
            {
                try
                {
                    process.Kill();
                    Log(String.Format("终止 Robocopy 进程: {0}", process.Id));
                }
                catch (Exception ex)
                {
                    Log(String.Format("终止进程 {0} 失败: {1}", process.Id, ex.Message));
                }
            }
            
            // ===== 终止 PowerShell 间接启动的 mysqldump 子进程 =====
            foreach (var process in System.Diagnostics.Process.GetProcessesByName("mysqldump"))
            {
                try
                {
                    process.Kill();
                    Log(String.Format("终止 mysqldump 进程: {0}", process.Id));
                }
                catch (Exception ex)
                {
                    Log(String.Format("终止进程 {0} 失败: {1}", process.Id, ex.Message));
                }
            }
            
            Log("所有备份相关进程已终止");
        }
        catch (Exception ex)
        {
            Log("终止进程时发生错误: " + ex.Message);
        }
    }
    
    private void Button3_Click(object sender, EventArgs e)
    {
        using (FolderBrowserDialog dialog = new FolderBrowserDialog())
        {
            if (dialog.ShowDialog() == DialogResult.OK)
            {
                textBox3.Text = dialog.SelectedPath;
                Log("备份根目录已设置为: " + dialog.SelectedPath);
            }
        }
    }
    
    private void Button4_Click(object sender, EventArgs e)
    {
        textBox2.Clear();
        // 先禁用 FileSystemWatcher，避免事件触发顺序问题
        if (logWatcher != null)
        {
            logWatcher.EnableRaisingEvents = false;
        }
        
        // 重置文件大小计数器（在清空文件之前）
        lastFileSize = 0;
        
        // 清空文件内容而不是删除文件，避免 FileSystemWatcher 失效
        try
        {
            File.WriteAllText(logFilePath, string.Empty);
        }
        catch (Exception ex)
        {
            Log("清空日志文件失败: " + ex.Message);
        }
        
        // 重新启用 FileSystemWatcher
        if (logWatcher != null)
        {
            logWatcher.EnableRaisingEvents = true;
        }
        
        // 直接在文本框显示消息，不依赖文件监控
        textBox2.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] 日志已清空\n");
        textBox2.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] lastFileSize = " + lastFileSize + "\n");
        textBox2.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] logWatcher = " + (logWatcher != null ? "Enabled" : "Null") + "\n");
        textBox2.ScrollToCaret();
    }
    
    // 清空操作记录按钮点击事件
    private void ButtonClearRecords_Click(object sender, EventArgs e)
    {
        if (dataGridView1.Rows.Count == 0)
        {
            MessageBox.Show("没有记录可清空！", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        
        DialogResult result = MessageBox.Show("确定要清空所有操作记录吗？此操作不可恢复！", "确认清空", 
            MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
        
        if (result == DialogResult.OK)
        {
            try
            {
                // 清空 DataGridView
                dataGridView1.Rows.Clear();
                
                // 删除记录文件
                string recordDir = "Records";
                string recordFile = Path.Combine(recordDir, "operation_records.txt");
                if (File.Exists(recordFile))
                {
                    File.Delete(recordFile);
                }
                
                Log("操作记录已清空");
                MessageBox.Show("操作记录已成功清空！", "成功", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Log("清空操作记录失败: " + ex.Message);
                MessageBox.Show("清空操作记录失败: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
    
    private void Button5_Click(object sender, EventArgs e)
    {
        SaveConfig();
        Log("配置已保存");
        MessageBox.Show("配置保存成功");
    }
    
    // 撤销备份按钮点击事件
    private void ButtonCancelBackup_Click(object sender, EventArgs e)
    {
        DialogResult result = MessageBox.Show("确定要强制取消所有备份操作吗？\n\n这将终止所有正在运行的备份进程（包括定时任务启动的自动备份），并禁用自动备份计划。", "确认撤销备份", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
        if (result == DialogResult.OK)
        {
            isWorking = false;
            
            // 发送跨进程取消信号
            if (cancelEventHandle != null)
            {
                try { cancelEventHandle.Set(); } catch { }
            }
            
            // 终止主进程
            System.Diagnostics.Process procToKill;
            lock (stateLock)
            {
                procToKill = currentProcess;
            }
            if (procToKill != null && !procToKill.HasExited)
            {
                try
                {
                    procToKill.Kill();
                    Log("主进程已被终止");
                }
                catch (Exception ex)
                {
                    Log("终止主进程时发生错误: " + ex.Message);
                }
                finally
                {
                    lock (stateLock)
                    {
                        currentProcess = null;
                    }
                }
            }
            
            // 终止所有相关的备份进程
            TerminateAllBackupProcesses();
            
            // 删除计划任务，防止下次自动执行
            DeleteScheduledTask("DataBackupTool_AutoBackup");
            
            // 释放互斥锁
            if (backupMutex != null)
            {
                try
                {
                    backupMutex.ReleaseMutex();
                    Log("互斥锁已释放");
                }
                catch { }
                backupMutex = null;
            }
            
            // 更新UI：取消自动备份勾选
            checkBox1.Checked = false;
            
            UpdateStatus("备份已撤销", Color.Red);
            Log("备份操作已被用户撤销，计划任务已删除");
            ResetUI();
            
            MessageBox.Show("所有备份操作已取消，自动备份计划已停用！", "撤销成功", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
    
    private void Button7_Click(object sender, EventArgs e)
    {
        using (FolderBrowserDialog dialog = new FolderBrowserDialog())
        {
            if (dialog.ShowDialog() == DialogResult.OK)
            {
                textBox4.Text = dialog.SelectedPath;
                Log("导入源目录已设置为: " + dialog.SelectedPath);
            }
        }
    }
    
    // 一键导入标签页的保存配置按钮点击事件
    private void ButtonSaveImportConfig_Click(object sender, EventArgs e)
    {
        // 保存导入相关配置到 config.txt
        try
        {
            string configContent = "BackupRoot=" + textBox3.Text + Environment.NewLine +
                                  "BackupTime=" + dateTimePicker1.Value.ToShortTimeString() + Environment.NewLine +
                                  "BackupContent=" + GetSelectedBackupContent() + Environment.NewLine +
                                  "DeleteAfterBackup=" + GetSelectedDeleteOption() + Environment.NewLine +
                                  "AutoBackup=" + checkBox1.Checked.ToString() + Environment.NewLine +
                                  "ImportPath=" + textBox4.Text + Environment.NewLine +
                                  "ImportContent=" + GetSelectedImportContent() + Environment.NewLine +
                                  "DuplicateOption=" + GetSelectedDuplicateOption() + Environment.NewLine +
                                  "AfterImport=" + GetSelectedAfterImport();
            string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.txt");
            File.WriteAllText(configPath, configContent, Encoding.UTF8);
            
            Log("导入配置已保存");
            MessageBox.Show("导入配置保存成功");
        }
        catch (Exception ex)
        {
            Log("保存导入配置失败: " + ex.Message);
            MessageBox.Show("保存配置失败: " + ex.Message);
        }
    }
    
    private void Button9_Click(object sender, EventArgs e)
    {
        string importPath = textBox4.Text.Trim();
        
        if (string.IsNullOrEmpty(importPath) || !Directory.Exists(importPath))
        {
            MessageBox.Show("请选择有效的导入源目录");
            return;
        }
        
        if (isWorking)
        {
            MessageBox.Show("正在执行操作，请等待完成");
            return;
        }
        
        if (radioButton15.Checked)
        {
            DialogResult result = MessageBox.Show("确定要在导入后删除备份文件吗？此操作不可恢复！", "确认删除", MessageBoxButtons.OKCancel);
            if (result != DialogResult.OK)
            {
                return;
            }
        }
        
        isWorking = true;
        button9.Enabled = false;
        textBox4.Enabled = false;
        
        UpdateStatus("正在导入...", Color.Blue);
        Log("开始一键导入，源目录: " + importPath + "，导入内容: " + GetSelectedImportContent() + "，重复数据处理: " + GetSelectedDuplicateOption() + "，导入后操作: " + GetSelectedAfterImport());
        
        ThreadPool.QueueUserWorkItem((state) =>
        {
            ExecuteBatchImport(importPath);
        });
    }
    
    // 执行备份操作主方法
    private void ExecuteBackup(string guid)
    {
        try
        {
            string backupContent = GetSelectedBackupContent();
            string deleteOption = GetSelectedDeleteOption();
            
            // 从配置文件读取备份路径
            string basePath = AppDomain.CurrentDomain.BaseDirectory;
            string dataBackupPath = Path.Combine(basePath, GetConfigValue("paths.dataBackupPath", "data"));
            string imageBackupPath = Path.Combine(basePath, GetConfigValue("paths.imageBackupPath", "vtImages_2D/images"));
            string schemaBackupPath = Path.Combine(basePath, GetConfigValue("paths.schemaBackupPath", "."));
            
            bool backupImage = backupContent == "仅图片" || backupContent == "图片+数据";
            bool backupData = backupContent == "仅数据" || backupContent == "图片+数据";
            
            int imageCount = 0;
            int dataCount = 0;
            
            if (backupImage)
            {
                string imageScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "imagecopy.ps1");
                string scriptError = "";
                int exitCode = RunPowerShellScript(imageScript, "-guid \"" + guid + "\"", out scriptError, imageBackupPath);
                if(exitCode != 0)
                {
                    Log("图片备份脚本执行失败，退出代码: " + exitCode);
                    string detailedError = "图片备份失败";
                    switch(exitCode)
                    {
                        case 1:
                        detailedError = "图片备份失败: GUID不在数据库中";
                        break;
                        case -1:
                        detailedError = "图片备份失败: 脚本文件不存在";
                        break;
                        case -2:
                        detailedError = "图片备份失败: 操作已被取消";
                        break;
                        default:
                        detailedError = "图片备份失败: 退出代码: " + exitCode;
                        break;

                    }
                    if(!string.IsNullOrEmpty(scriptError))
                    {
                        if(scriptError.Contains("GUID not found"))
                        {
                            detailedError = "图片备份失败: GUID不存在于数据库中";
                        }
                        else if(scriptError.Contains("Error:"))
                        {
                            int errorIndex = scriptError.IndexOf("Error:");
                            if(errorIndex >0)
                            {
                                string extractedError = scriptError.Substring(errorIndex);
                                detailedError = "图片备份失败: " + extractedError;
                            }
                        }
                    }
                    throw new Exception(detailedError);
                }
                
                string guidImageDir = Path.Combine(imageBackupPath, guid, "images");
                if (Directory.Exists(guidImageDir))
                {
                    imageCount = Directory.GetFiles(guidImageDir, "*.*", SearchOption.AllDirectories).Length;
                }
            }
            
            if (backupData)
            {
                string dataScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "GUID-Data.ps1");
                string psError;
                int dataExitCode = RunPowerShellScript(dataScript, "-guid \"" + guid + "\"", out psError, dataBackupPath);
                if (dataExitCode != 0)
                {
                    throw new Exception("数据导出失败，退出代码: " + dataExitCode + "，错误信息: " + (psError ?? "未知错误"));
                }
                
                string schemaScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "schema.ps1");
                int schemaExitCode = RunPowerShellScript(schemaScript, "-guid \"" + guid + "\"", out psError, schemaBackupPath);
                if (schemaExitCode != 0)
                {
                    throw new Exception("表结构导出失败，退出代码: " + schemaExitCode + "，错误信息: " + (psError ?? "未知错误"));
                }
                
                string guidDataDir = Path.Combine(dataBackupPath, guid);
                if (Directory.Exists(guidDataDir))
                {
                    dataCount = Directory.GetFiles(guidDataDir, "*.sql", SearchOption.TopDirectoryOnly).Length;
                }
            }
            
            Log("备份成功！共复制 " + imageCount + " 张图片，导出 " + dataCount + " 个数据表");
            SaveBackupRecord(guid, true, imageCount, dataCount, null);
            
            if (deleteOption == "删除数据")
            {
                DeleteAfterBackup(guid, deleteOption);
            }
            
            this.Invoke((MethodInvoker)delegate
            {
                UpdateStatus("系统就绪", Color.LawnGreen);
                ResetUI();
                MessageBox.Show("备份成功！共复制 " + imageCount + " 张图片，导出 " + dataCount + " 个数据表");
            });
        }
        catch (Exception ex)
        {
            Log("备份失败: " + ex.Message);
            SaveBackupRecord(guid, false, 0, 0, ex.Message);
            
            this.Invoke((MethodInvoker)delegate
            {
                UpdateStatus("操作失败", Color.Red);
                ResetUI();
                MessageBox.Show("备份失败: " + ex.Message);
            });
        }
    }
    
    // 执行单GUID导入操作
    private void ExecuteImport(string guid)
    {
        try
        {
            Log("执行单GUID导入...");
            
            string importContent = GetSelectedImportContent();
            string duplicateOption = GetSelectedDuplicateOption();
            string afterImport = GetSelectedAfterImport();
            
            bool importImage = importContent == "仅图片" || importContent == "图片+数据";
            bool importData = importContent == "仅数据" || importContent == "图片+数据";
            
            if (importData)
            {
                string importScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ImportWorker.ps1");
                // 获取导入路径，若为空则使用程序运行目录
                string importPath = (string.IsNullOrEmpty(textBox4.Text.Trim()) ? AppDomain.CurrentDomain.BaseDirectory : textBox4.Text).TrimEnd('\\');
                if (!Directory.Exists(importPath))
                {
                    throw new Exception("导入源目录不存在: " + importPath);
                }
                string dataDir = Path.Combine(importPath, "data");
                if (!Directory.Exists(dataDir))
                {
                    throw new Exception("导入源目录下缺少 data 文件夹: " + dataDir);
                }
                string args = "-guid \"" + guid + "\" -path \"" + importPath + "\" -duplicateOption \"" + duplicateOption + "\"";
                string psError;
                int exitCode = RunPowerShellScript(importScript, args, out psError, "");
                if (exitCode != 0)
                {
                    throw new Exception("导入脚本执行失败，退出代码: " + exitCode + "，错误信息: " + (psError ?? "未知错误"));
                }
            }
            
            // 导入完成后检查是否需要删除备份文件
            if (afterImport == "删除备份文件")
            {
                // 获取基础路径，若为空则使用程序运行目录
                string basePath = string.IsNullOrEmpty(textBox4.Text.Trim()) ? AppDomain.CurrentDomain.BaseDirectory : textBox4.Text;
                
                string dataPath = Path.Combine(basePath, "data", guid);
                string imagePath = Path.Combine(basePath, "vtImages_2D", "images", guid);
                string schemaPath = Path.Combine(basePath, "schema", guid);
                
                if (Directory.Exists(dataPath))
                {
                    try
                    {
                        Directory.Delete(dataPath, true);
                        Log("数据备份文件已删除: " + dataPath);
                    }
                    catch (Exception ex)
                    {
                        Log("删除数据备份文件失败: " + ex.Message);
                    }
                }
                if (Directory.Exists(imagePath))
                {
                    try
                    {
                        Directory.Delete(imagePath, true);
                        Log("图片备份文件已删除: " + imagePath);
                    }
                    catch (Exception ex)
                    {
                        Log("删除图片备份文件失败: " + ex.Message);
                    }
                }
                if (Directory.Exists(schemaPath))
                {
                    try
                    {
                        Directory.Delete(schemaPath, true);
                        Log("Schema备份文件已删除: " + schemaPath);
                    }
                    catch (Exception ex)
                    {
                        Log("删除Schema备份文件失败: " + ex.Message);
                    }
                }
            }
            
            Log("单GUID导入完成！");
            
            SaveOperationRecord(guid, "导入", "成功", textBox4.Text, "", "单GUID导入完成", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            
            this.Invoke((MethodInvoker)delegate
            {
                UpdateStatus("系统就绪", Color.LawnGreen);
                ResetUI();
                MessageBox.Show("导入成功！");
            });
        }
        catch (Exception ex)
        {
            Log("导入失败: " + ex.Message);
            
            SaveOperationRecord(guid, "导入", "失败", textBox4.Text, "", "导入失败: " + ex.Message, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            
            this.Invoke((MethodInvoker)delegate
            {
                UpdateStatus("操作失败", Color.Red);
                ResetUI();
                MessageBox.Show("导入失败: " + ex.Message);
            });
        }
    }
    
    // 执行批量导入操作
    private void ExecuteBatchImport(string importPath)
    {
        try
        {
            string importContent = GetSelectedImportContent();
            string duplicateOption = GetSelectedDuplicateOption();
            string afterImport = GetSelectedAfterImport();
            
            bool importImage = importContent == "仅图片" || importContent == "图片+数据";
            bool importData = importContent == "仅数据" || importContent == "图片+数据";
            
            if (importData)
            {
                string importScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ImportWorker.ps1");
                if (!Directory.Exists(importPath))
                {
                    throw new Exception("导入源目录不存在: " + importPath);
                }
                string dataDir = Path.Combine(importPath, "data");
                if (!Directory.Exists(dataDir))
                {
                    throw new Exception("导入源目录下缺少 data 文件夹: " + dataDir);
                }
                string args = "-path \"" + importPath.TrimEnd('\\') + "\" -duplicateOption \"" + duplicateOption + "\"";
                string psError;
                int exitCode = RunPowerShellScript(importScript, args, out psError, "");
                if (exitCode != 0)
                {
                    throw new Exception("一键导入脚本执行失败，退出代码: " + exitCode + "，错误信息: " + (psError ?? "未知错误"));
                }
            }
            
            if (afterImport == "删除备份文件" && Directory.Exists(importPath))
            {
                try
                {
                    Directory.Delete(importPath, true);
                    Log("备份文件已删除");
                }
                catch (Exception ex)
                {
                    Log("删除备份文件失败: " + ex.Message);
                }
            }
            
            Log("一键导入完成！");
            
            SaveOperationRecord("批量导入", "导入", "成功", importPath, "", "一键导入完成", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            
            this.Invoke((MethodInvoker)delegate
            {
                UpdateStatus("系统就绪", Color.LawnGreen);
                ResetUI();
                MessageBox.Show("一键导入完成！");
            });
        }
        catch (Exception ex)
        {
            Log("一键导入失败: " + ex.Message);
            
            SaveOperationRecord("批量导入", "导入", "失败", importPath, "", "一键导入失败: " + ex.Message, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            
            this.Invoke((MethodInvoker)delegate
            {
                UpdateStatus("操作失败", Color.Red);
                ResetUI();
                MessageBox.Show("一键导入失败: " + ex.Message);
            });
        }
    }
    
    private void DeleteAfterBackup(string guid, string deleteOption)
    {
        try
        {
            if (deleteOption == "删除数据")
            {
                Log("执行备份后删除操作: " + deleteOption);
                string deleteScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "DeleteData.ps1");
                string psError;
                int exitCode = RunPowerShellScript(deleteScript, "\"" + guid + "\"", out psError);
                if (exitCode != 0)
                {
                    Log("备份后删除操作失败，退出代码: " + exitCode);
                }
            }
        }
        catch (Exception ex)
        {
            Log("删除操作失败: " + ex.Message);
        }
    }
    
    // 执行PowerShell脚本的通用方法
    private int RunPowerShellScript(string scriptPath, string argument, out string errorMessage, string extraParam = "")
    {
        errorMessage = null;
        try
        {
            if (!File.Exists(scriptPath))
            {
                Log("错误: 脚本文件不存在 - " + scriptPath);
                return -1;
            }
            
            if (!isWorking)
            {
                Log("操作已被取消，跳过脚本执行");
                return -2;
            }
            
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            
            // 设置工作目录为脚本所在目录，确保 $PSScriptRoot 变量可用
            psi.WorkingDirectory = Path.GetDirectoryName(scriptPath);
            
            string args = "-ExecutionPolicy Bypass -File \"" + scriptPath + "\"";
            if (!string.IsNullOrEmpty(argument))
            {
                args += " " + argument;
            }
            if (!string.IsNullOrEmpty(extraParam))
            {
                args += " -path \"" + extraParam.TrimEnd('\\') + "\"";
            }
            
            psi.Arguments = args;
            Log("执行脚本: powershell.exe " + args);
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.StandardOutputEncoding = System.Text.Encoding.UTF8;
            psi.StandardErrorEncoding = System.Text.Encoding.UTF8;
            
            System.Diagnostics.Process localProcess = Process.Start(psi);
            lock (stateLock)
            {
                currentProcess = localProcess;
            }
            
            if (localProcess == null)
            {
                Log("无法启动进程");
                return -3;
            }
            
            // 记录子进程 PID，用于精确终止
            lock (pidLock)
            {
                childProcessPids.Add(localProcess.Id);
            }
            
            string output = localProcess.StandardOutput.ReadToEnd();
            string error = localProcess.StandardError.ReadToEnd();
            localProcess.WaitForExit();
            
            if (!string.IsNullOrEmpty(output))
                Log(output);
            if (!string.IsNullOrEmpty(error))
            {
                string filteredError = error;
                if (error.Contains("Using a password on the command line interface can be insecure"))
                {
                    filteredError = error.Replace("Using a password on the command line interface can be insecure","");
                }
                if (!string.IsNullOrEmpty(filteredError.Trim()))
                {
                    Log("错误：" + filteredError.Trim());
                    errorMessage = filteredError.Trim();
                }
            }
            int exitCode = localProcess.ExitCode;
            // 如果用户已取消，覆盖退出码为"已取消"，避免误报其他错误
            if (!isWorking)
            {
                exitCode = -2;
            }
            lock (pidLock)
            {
                childProcessPids.Remove(localProcess.Id);
            }
            lock (stateLock)
            {
                currentProcess = null;
            }
            return exitCode;
        }
        catch (Exception ex)
        {
            // 如果是用户取消操作，不记录错误日志
            if (isWorking)
            {
                Log("执行脚本失败: " + ex.Message);
                errorMessage = ex.Message;
            }
            System.Diagnostics.Process proc = null;
            lock (stateLock)
            {
                proc = currentProcess;
            }
            if (proc != null)
            {
                lock (pidLock)
                {
                    childProcessPids.Remove(proc.Id);
                }
            }
            lock (stateLock)
            {
                currentProcess = null;
            }
            return -99;
        }
    }
    
    // 加载已有操作记录
    private void LoadOperationRecords()
    {
        try
        {
            string recordDir = "Records";
            string recordFile = Path.Combine(recordDir, "operation_records.txt");
            
            if (!File.Exists(recordFile))
            {
                return;
            }
            
            string[] lines = File.ReadAllLines(recordFile);
            
            foreach (string line in lines)
            {
                if (string.IsNullOrWhiteSpace(line))
                    continue;
                
                string[] parts = line.Split('|');
                if (parts.Length >= 7)
                {
                    string createTime = parts[0];
                    string guid = parts[1];
                    string operationType = parts[2];
                    string status = parts[3];
                    string backupPath = parts[4];
                    string startTime = parts[5];
                    string log = parts[6];
                    
                    AddRecordToGridView(guid, status, operationType, backupPath, "0", startTime, log, createTime);
                }
            }
            
            Log("操作记录加载完成");
        }
        catch (Exception ex)
        {
            Log("加载操作记录失败: " + ex.Message);
        }
    }
    
    // 保存操作记录到文件和DataGridView
    private void SaveOperationRecord(string guid, string operationType, string status, string backupPath, string startTime, string log, string createTime)
    {
        try
        {
            string recordDir = "Records";
            string recordFile = Path.Combine(recordDir, "operation_records.txt");
            
            if (!Directory.Exists(recordDir))
            {
                Directory.CreateDirectory(recordDir);
            }
            
            string recordLine = createTime + "|" + guid + "|" + operationType + "|" + status + "|" + (backupPath ?? "") + "|" + (startTime ?? "") + "|" + (log ?? "");
            File.AppendAllText(recordFile, recordLine + Environment.NewLine, Encoding.UTF8);
            
            AddRecordToGridView(guid, status, operationType, backupPath, "0", startTime, log, createTime);
            
            Log("操作记录已保存");
        }
        catch (Exception ex)
        {
            Log("保存操作记录失败: " + ex.Message);
        }
    }
    
    // 添加记录到DataGridView
    private void AddRecordToGridView(string guid, string status, string type, string path, string retry, string startTime, string log, string createTime)
    {
        if (dataGridView1.InvokeRequired)
        {
            dataGridView1.Invoke(new Action<string, string, string, string, string, string, string, string>(AddRecordToGridView), 
                guid, status, type, path, retry, startTime, log, createTime);
            return;
        }
        
        int rowIndex = dataGridView1.Rows.Add();
        DataGridViewRow row = dataGridView1.Rows[rowIndex];
        row.Cells["colGuid"].Value = guid;
        row.Cells["colStatus"].Value = status;
        row.Cells["colType"].Value = type;
        row.Cells["colPath"].Value = path;
        row.Cells["colRetry"].Value = retry;
        row.Cells["colStartTime"].Value = startTime;
        row.Cells["colLog"].Value = log;
        row.Cells["colCreateTime"].Value = createTime;
        
        if (status == "成功")
        {
            row.Cells["colStatus"].Style.ForeColor = Color.Green;
        }
        else if (status == "失败")
        {
            row.Cells["colStatus"].Style.ForeColor = Color.Red;
        }
        else
        {
            row.Cells["colStatus"].Style.ForeColor = Color.Orange;
        }
    }
    
    // DataGridView按钮点击事件
    private void DataGridView1_CellContentClick(object sender, DataGridViewCellEventArgs e)
    {
        if (e.ColumnIndex == dataGridView1.Columns["colAction"].Index && e.RowIndex >= 0)
        {
            string guid = dataGridView1.Rows[e.RowIndex].Cells["colGuid"].Value.ToString();
            object logObj = dataGridView1.Rows[e.RowIndex].Cells["colLog"].Value;
            string log = logObj != null ? logObj.ToString() : "";
            
            MessageBox.Show(String.Format("批次GUID: {0}\n\n任务日志:\n{1}", guid, log), "操作详情", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
    
    // 保存备份记录到文件（兼容旧调用）
    private void SaveBackupRecord(string guid, bool success, int imageCount, int dataCount, string errorMsg)
    {
        string status = success ? "成功" : "失败";
        string log = success ? String.Format("复制 {0} 张图片，导出 {1} 个数据表", imageCount, dataCount) : errorMsg;
        string backupPath = Path.Combine(textBox3.Text, guid);
        
        SaveOperationRecord(guid, "备份", status, backupPath, "", log, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
    }
    
    // 保存配置到文件并更新计划任务
    private void SaveConfig()
        {
            try
            {
                string configContent = "BackupRoot=" + textBox3.Text + Environment.NewLine +
                                      "BackupTime=" + dateTimePicker1.Value.ToShortTimeString() + Environment.NewLine +
                                      "BackupContent=" + GetSelectedBackupContent() + Environment.NewLine +
                                      "DeleteAfterBackup=" + GetSelectedDeleteOption() + Environment.NewLine +
                                      "AutoBackup=" + checkBox1.Checked.ToString() + Environment.NewLine +
                                      "ImportPath=" + textBox4.Text + Environment.NewLine +
                                      "ImportContent=" + GetSelectedImportContent() + Environment.NewLine +
                                      "DuplicateOption=" + GetSelectedDuplicateOption() + Environment.NewLine +
                                      "AfterImport=" + GetSelectedAfterImport();
                string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.txt");
                File.WriteAllText(configPath, configContent, Encoding.UTF8);
                
                // 只有启用自动备份时才管理计划任务
                // 未启用时：完全不碰计划任务（用户只是保存手动备份配置）
                // 已启用时：先删除旧任务（确保参数更新），再创建新任务
                if (checkBox1.Checked)
                {
                    string backupTime = dateTimePicker1.Value.ToString("HH:mm:ss");
                    // 先删除旧的计划任务，确保只有一个任务存在
                    if (!DeleteScheduledTask("DataBackupTool_AutoBackup"))
                    {
                        Log("删除旧计划任务失败（可能不存在），继续创建新任务");
                    }
                    CreateScheduledTask("DataBackupTool_AutoBackup", backupTime);
                }
            }
            catch (Exception ex)
            {
                Log("保存配置失败: " + ex.Message);
            }
        }
        
        // 自动备份复选框状态变化处理
        private void checkBox1_CheckedChanged(object sender, EventArgs e)
        {
            if (checkBox1.Checked)
            {
                checkBox1.Text = "已启用";
                checkBox1.ForeColor = Color.Green;
                Log("Auto backup enabled");
            }
            else
            {
                checkBox1.Text = "未启用";
                checkBox1.ForeColor = Color.Red;
                Log("Auto backup disabled");
            }
        }
        
        // 从配置文件加载配置
        private void LoadConfig()
        {
            try
            {
                string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.txt");
                if (File.Exists(configPath))
                {
                    // 使用UTF-8编码读取配置文件，与保存时一致
                    string[] lines = File.ReadAllLines(configPath, Encoding.UTF8);
                    foreach (string line in lines)
                    {
                        if (line.StartsWith("BackupRoot="))
                        {
                            textBox3.Text = line.Substring("BackupRoot=".Length);
                        }
                        else if (line.StartsWith("BackupTime="))
                        {
                            string timeStr = line.Substring("BackupTime=".Length);
                            DateTime backupTime;
                            if (DateTime.TryParse(timeStr, out backupTime))
                            {
                                dateTimePicker1.Value = backupTime;
                            }
                        }
                        else if (line.StartsWith("BackupContent="))
                        {
                            string content = line.Substring("BackupContent=".Length);
                            radioButton1.Checked = (content == "仅图片");
                            radioButton2.Checked = (content == "仅数据");
                            radioButton3.Checked = (content == "图片+数据");
                        }
                        else if (line.StartsWith("DeleteAfterBackup="))
                        {
                            string option = line.Substring("DeleteAfterBackup=".Length);
                            radioButton5.Checked = (option == "删除数据");
                            radioButton6.Checked = (option == "暂不删除");
                        }
                        else if (line.StartsWith("AutoBackup="))
                        {
                            bool autoBackupEnabled;
                            if (bool.TryParse(line.Substring("AutoBackup=".Length), out autoBackupEnabled))
                            {
                                checkBox1.Checked = autoBackupEnabled;
                                checkBox1.Text = autoBackupEnabled ? "已启用" : "未启用";
                                checkBox1.ForeColor = autoBackupEnabled ? Color.Green : Color.Red;
                            }
                        }
                        else if (line.StartsWith("ImportPath="))
                        {
                            textBox4.Text = line.Substring("ImportPath=".Length);
                        }
                        else if (line.StartsWith("DuplicateOption="))
                        {
                            string option = line.Substring("DuplicateOption=".Length);
                            // 如果配置值有效则使用配置，否则默认选中"追加导入"
                            if (option == "覆盖重复")
                            {
                                radioButton12.Checked = true;
                                radioButton11.Checked = false;
                                radioButton13.Checked = false;
                            }
                            else if (option == "清空后导入")
                            {
                                radioButton13.Checked = true;
                                radioButton11.Checked = false;
                                radioButton12.Checked = false;
                            }
                            else
                            {
                                // 默认选中"追加导入"（包括空值或无效值的情况）
                                radioButton11.Checked = true;
                                radioButton12.Checked = false;
                                radioButton13.Checked = false;
                            }
                        }
                        else if (line.StartsWith("AfterImport="))
                        {
                            string option = line.Substring("AfterImport=".Length);
                            radioButton14.Checked = (option == "保留备份文件");
                            radioButton15.Checked = (option == "删除备份文件");
                        }
                    }
                }
                
                // 兜底逻辑：确保导入选择处理至少有一个选项被选中
                if (!radioButton11.Checked && !radioButton12.Checked && !radioButton13.Checked)
                {
                    radioButton11.Checked = true;
                    radioButton12.Checked = false;
                    radioButton13.Checked = false;
                }
                
                // 加载数据库配置
                LoadDatabaseConfig();
            }
            catch (Exception ex)
            {
                Log("加载配置失败：" + ex.Message);
            }
        }
    
    // 加载数据库配置
    private void LoadDatabaseConfig()
    {
        try
        {
            string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.json");
            if (File.Exists(configPath))
            {
                string jsonContent = File.ReadAllText(configPath);
                
                // 加载备份数据库配置
                LoadDatabaseSection(jsonContent, "backupMysql", 
                    textBoxBackupDbHost, textBoxBackupDbPort, textBoxBackupDbUser, 
                    textBoxBackupDbPassword, textBoxBackupDbName);
                
                // 加载导入数据库配置
                LoadDatabaseSection(jsonContent, "importMysql", 
                    textBoxImportDbHost, textBoxImportDbPort, textBoxImportDbUser, 
                    textBoxImportDbPassword, textBoxImportDbName);
            }
        }
        catch (Exception ex)
        {
            Log("加载数据库配置失败：" + ex.Message);
        }
    }
    
    // 加载数据库配置节
    private void LoadDatabaseSection(string jsonContent, string sectionName, 
        TextBox hostBox, TextBox portBox, TextBox userBox, TextBox passwordBox, TextBox nameBox)
    {
        try
        {
            // 查找配置节
            int dbSectionStart = jsonContent.IndexOf(string.Format("\"{0}\":", sectionName));
            if (dbSectionStart != -1)
            {
                int dbSectionEnd = jsonContent.IndexOf("}", dbSectionStart);
                if (dbSectionEnd != -1)
                {
                    string dbSection = jsonContent.Substring(dbSectionStart, dbSectionEnd - dbSectionStart);
                    
                    // 提取各个字段
                    if (dbSection.Contains("\"host\":"))
                    {
                        hostBox.Text = ExtractJsonValue(dbSection, "host");
                    }
                    if (dbSection.Contains("\"port\":"))
                    {
                        portBox.Text = ExtractJsonValue(dbSection, "port");
                    }
                    if (dbSection.Contains("\"user\":"))
                    {
                        userBox.Text = ExtractJsonValue(dbSection, "user");
                    }
                    if (dbSection.Contains("\"password\":"))
                    {
                        passwordBox.Text = ExtractJsonValue(dbSection, "password");
                    }
                    if (dbSection.Contains("\"database\":"))
                    {
                        nameBox.Text = ExtractJsonValue(dbSection, "database");
                    }
                }
            }
        }
        catch { }
    }
    
    // 从 JSON 字符串中提取指定字段的值
    private string ExtractJsonValue(string json, string fieldName)
    {
        try
        {
            int fieldStart = json.IndexOf(string.Format("\"{0}\":", fieldName));
            if (fieldStart != -1)
            {
                int valueStart = json.IndexOf(":", fieldStart) + 1;
                while (valueStart < json.Length && (json[valueStart] == ' ' || json[valueStart] == '"'))
                {
                    if (json[valueStart] == '"')
                    {
                        valueStart++;
                        break;
                    }
                    valueStart++;
                }
                int valueEnd = json.IndexOf("\"", valueStart);
                if (valueEnd != -1)
                {
                    return json.Substring(valueStart, valueEnd - valueStart);
                }
            }
        }
        catch { }
        return "";
    }
    
    //创建Windows计划任务的方法，用于设置自动备份的定时执行
    private bool CreateScheduledTask(string taskName, string triggerTime)
        {
            try
            {
                string exePath = Application.ExecutablePath;
                string arguments = "-auto";
                // 对于schtasks命令，/tr参数内的引号需要用反斜杠转义
                string action = string.Format("\\\"{0}\\\" {1}", exePath, arguments);
                //创建进程对象
                using (System.Diagnostics.Process process = new System.Diagnostics.Process())
                {
                    process.StartInfo.FileName = "schtasks.exe";//Windows自带的计划任务管理工具
                    string currentUser = Environment.UserName;
                    process.StartInfo.Arguments = string.Format(
                        "/create /tn \"{0}\" /tr \"{1}\" /sc daily /st {2} /ru \"{3}\" /IT /f",
                        taskName, action, triggerTime, currentUser
                    );//创建计划任务的参数,包括任务名称、执行操作、执行时间、开始时间、用户、是否交互式、是否强制创建
                    process.StartInfo.UseShellExecute = false;//不使用ShellExecute，直接执行命令
                    process.StartInfo.RedirectStandardOutput = true;//重定向标准输出到进程对象
                    process.StartInfo.RedirectStandardError = true;//重定向标准错误到进程对象
                    process.StartInfo.CreateNoWindow = true;//创建无窗口的进程
                    
                    process.Start();
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    
                    if (process.ExitCode == 0)
                    {
                        Log("Scheduled task created successfully");
                        return true;
                    }
                    else
                    {
                        Log("Failed to create scheduled task: " + error);
                        return false;
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Error creating scheduled task: " + ex.Message);
                return false;
            }
        }
        
        //删除Windows计划任务的方法，用于取消自动备份的定时执行
        private bool DeleteScheduledTask(string taskName)
        {
            try
            {
                using (System.Diagnostics.Process process = new System.Diagnostics.Process())
                {
                    process.StartInfo.FileName = "schtasks.exe";
                    process.StartInfo.Arguments = string.Format("/delete /tn \"{0}\" /f", taskName);
                    process.StartInfo.UseShellExecute = false;
                    process.StartInfo.RedirectStandardOutput = true;
                    process.StartInfo.RedirectStandardError = true;
                    process.StartInfo.CreateNoWindow = true;
                    
                    process.Start();
                    process.WaitForExit();
                    
                    if (process.ExitCode == 0)
                    {
                        Log("Scheduled task deleted successfully");
                        return true;
                    }
                    else
                    {
                        Log("Failed to delete scheduled task");
                        return false;
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Error deleting scheduled task: " + ex.Message);
                return false;
            }
        }
        
        
        //重置用户界面的方法，用于在操作完成后重置用户界面
        private void ResetUI()
        {
            isWorking = false;
            button1.Enabled = IsValidGuid(textBox1.Text.Trim());
            button9.Enabled = !string.IsNullOrEmpty(textBox4.Text) && Directory.Exists(textBox4.Text);
            textBox1.Enabled = true;
            textBox4.Enabled = true;
            comboBox1.Enabled = true;
        }
    
    // 窗体关闭前的确认处理
    private void DataBackupTool_FormClosing(object sender, FormClosingEventArgs e)
    {
        if (isWorking)
        {
            DialogResult result = MessageBox.Show("正在执行操作，确定要退出吗？", "确认退出", MessageBoxButtons.OKCancel);
            if (result == DialogResult.Cancel)
            {
                e.Cancel = true;
                return;
            }
            // 用户确认退出，终止所有子进程
            isWorking = false;
            if (cancelEventHandle != null)
            {
                try { cancelEventHandle.Set(); } catch { }
            }
            TerminateAllBackupProcesses();
        }
        // 清理资源
        if (logWatcher != null)
        {
            logWatcher.EnableRaisingEvents = false;
            logWatcher.Dispose();
            logWatcher = null;
        }
        if (cancelEventHandle != null)
        {
            try { cancelEventHandle.Dispose(); } catch { }
            cancelEventHandle = null;
        }
        if (backupMutex != null)
        {
            try { backupMutex.ReleaseMutex(); } catch { }
            try { backupMutex.Dispose(); } catch { }
            backupMutex = null;
        }
    }
    
    // 程序入口方法
    [STAThread]
    public static void Main(string[] args)
    {
        string exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
        string exeDir = Path.GetDirectoryName(exePath);
        
        string repoRoot = exeDir;
        while (!string.IsNullOrEmpty(repoRoot) && !File.Exists(Path.Combine(repoRoot, "config.json")))
        {
            DirectoryInfo parent = Directory.GetParent(repoRoot);
            repoRoot = parent != null ? parent.FullName : null;
        }
        
        if (!string.IsNullOrEmpty(repoRoot))
        {
            Directory.SetCurrentDirectory(repoRoot);
        }
        
        if (args.Length > 0 && args[0].Equals("-auto", StringComparison.OrdinalIgnoreCase))
        {
            DataBackupTool.PerformAutoBackup();
            return;
        }
        
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new DataBackupTool());
    }
    
    // 从 config.json 读取配置值
    private string GetConfigValue(string key, string defaultValue)
    {
        try
        {
            string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.json");
            if (File.Exists(configPath))
            {
                string jsonContent = File.ReadAllText(configPath);
                // 简单的 JSON 解析
                string[] keyParts = key.Split('.');
                if (keyParts.Length == 2)
                {
                    string section = keyParts[0];
                    string field = keyParts[1];
                    
                    // 查找 section
                    int sectionStart = jsonContent.IndexOf(string.Format("\"{0}\":", section));
                    if (sectionStart != -1)
                    {
                        int sectionEnd = jsonContent.IndexOf("}", sectionStart);
                        if (sectionEnd != -1)
                        {
                            string sectionContent = jsonContent.Substring(sectionStart, sectionEnd - sectionStart);
                            int fieldStart = sectionContent.IndexOf(string.Format("\"{0}\":", field));
                            if (fieldStart != -1)
                            {
                                int valueStart = sectionContent.IndexOf(":", fieldStart) + 1;
                                int valueEnd = sectionContent.IndexOf(",", valueStart);
                                if (valueEnd == -1) valueEnd = sectionContent.IndexOf("}", valueStart);
                                
                                string value = sectionContent.Substring(valueStart, valueEnd - valueStart).Trim();
                                // 去除引号
                                if (value.StartsWith("\"")) value = value.Substring(1);
                                if (value.EndsWith("\"")) value = value.Substring(0, value.Length - 1);
                                return value;
                            }
                        }
                    }
                }
            }
        }
        catch { }
        
        return defaultValue;
    }
    
    // 执行自动备份（定时任务触发）
    public static void PerformAutoBackup()
    {
        RunAutoBackup(WriteLog);
    }
    
    // 静态日志写入方法（用于定时任务）
    private static void WriteLog(string message)
    {
        string logLine = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message;
        Console.WriteLine(logLine);
        WriteLogToFile(logLine);
    }
    
    // 将日志写入文件（静态方法）
    private static void WriteLogToFile(string message)
    {
        try
        {
            if (string.IsNullOrEmpty(staticLogFilePath))
            {
                string exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                string exeDir = Path.GetDirectoryName(exePath);
                staticLogFilePath = Path.Combine(exeDir, "backup_log.txt");
            }
            
            string logLine;
            // 如果消息已经包含时间戳格式（以 [ 开头），则直接使用，否则添加时间戳
            if (message.StartsWith("["))
            {
                logLine = message;
            }
            else
            {
                logLine = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message;
            }
            
            // 使用共享模式写入，允许 FileSystemWatcher 同时读取
            using (FileStream fs = new FileStream(staticLogFilePath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
            using (StreamWriter writer = new StreamWriter(fs, new System.Text.UTF8Encoding(true))) // 带 BOM 的 UTF-8
            {
                writer.WriteLine(logLine);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("Failed to write log: {0}", ex.Message);
        }
    }
    
    // 共享的自动备份执行逻辑
    private static void RunAutoBackup(Action<string> logCallback)
    {
        // 尝试获取互斥锁，确保只有一个备份进程运行
        bool mutexAcquired = false;
        try
        {
            // 创建或打开全局互斥锁
            backupMutex = new System.Threading.Mutex(false, "Global\\DataBackupTool_Mutex", out mutexAcquired);
            
            if (!mutexAcquired)
            {
                logCallback("检测到另一个备份进程正在运行，本次自动备份已跳过");
                return;
            }
            
            logCallback("互斥锁已获取，开始自动备份");
            
            // 重置取消信号，清除上次取消遗留的状态
            if (cancelEventHandle != null)
            {
                try { cancelEventHandle.Reset(); } catch { }
            }
            
            // 设置工作状态标志
            isWorking = true;
            
            try
            {
                string exeDir = Path.GetDirectoryName(
                    System.Reflection.Assembly.GetExecutingAssembly().Location);
                
                string autoBackupScript = Path.Combine(exeDir, "AutoBackup.ps1");
                
                if (!File.Exists(autoBackupScript))
                {
                    logCallback("AutoBackup.ps1 not found in " + exeDir);
                    return;
                }
                
                // 创建进程并保存到静态变量以便取消操作可以访问
                var autoProcess = new System.Diagnostics.Process();
                autoProcess.StartInfo.FileName = "powershell.exe";
                autoProcess.StartInfo.Arguments = "-ExecutionPolicy Bypass -File \"" + autoBackupScript + "\" -auto";
                autoProcess.StartInfo.UseShellExecute = false;
                autoProcess.StartInfo.RedirectStandardOutput = true;
                autoProcess.StartInfo.RedirectStandardError = true;
                autoProcess.StartInfo.StandardOutputEncoding = System.Text.Encoding.UTF8;
                autoProcess.StartInfo.StandardErrorEncoding = System.Text.Encoding.UTF8;
                autoProcess.StartInfo.CreateNoWindow = true;
                autoProcess.StartInfo.WorkingDirectory = exeDir;
                
                autoProcess.OutputDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        // PowerShell脚本已经写入自己的日志文件(auto_backup_log.txt)
                        // 这里只通过回调显示到UI，不再写入文件避免重复
                        if (e.Data.StartsWith("["))
                        {
                            // 已经有时间戳，直接写入文件
                            WriteLogToFile(e.Data);
                        }
                        else
                        {
                            logCallback(e.Data);
                        }
                    }
                };
                
                autoProcess.ErrorDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        // 错误信息统一通过回调处理
                        logCallback("Error: " + e.Data);
                    }
                };
                
                lock (stateLock) { currentProcess = autoProcess; }
                autoProcess.Start();
                lock (pidLock)
                {
                    childProcessPids.Add(autoProcess.Id);
                }
                autoProcess.BeginOutputReadLine();
                autoProcess.BeginErrorReadLine();
                // 周期性检查取消信号，而非无限等待
                while (!autoProcess.HasExited)
                {
                    if (cancelEventHandle != null && cancelEventHandle.WaitOne(0))
                    {
                        logCallback("检测到取消信号，正在终止自动备份...");
                        try { autoProcess.Kill(); } catch { }
                        break;
                    }
                    autoProcess.WaitForExit(2000);
                }
            }
            catch (Exception ex)
            {
                // 如果是用户取消操作，不记录错误日志
                if (isWorking)
                {
                    logCallback("Error during auto backup: " + ex.Message);
                }
            }
            finally
            {
                // 确保进程资源被释放
                System.Diagnostics.Process procToClean = null;
                lock (stateLock)
                {
                    procToClean = currentProcess;
                }
                if (procToClean != null)
                {
                    lock (pidLock)
                    {
                        childProcessPids.Remove(procToClean.Id);
                    }
                    try
                    {
                        procToClean.Dispose();
                    }
                    catch { }
                    lock (stateLock)
                    {
                        currentProcess = null;
                    }
                }
                // 重置工作状态标志
                isWorking = false;
            }
        }
        finally
        {
            // 释放互斥锁
            if (mutexAcquired && backupMutex != null)
            {
                try
                {
                    backupMutex.ReleaseMutex();
                    logCallback("互斥锁已释放");
                }
                catch { }
                backupMutex.Dispose();
                backupMutex = null;
            }
        }
    }
    
    // 测试备份数据库连接按钮点击事件
    private void ButtonTestBackupConnection_Click(object sender, EventArgs e)
    {
        TestDatabaseConnection(
            textBoxBackupDbHost.Text.Trim(),
            textBoxBackupDbPort.Text.Trim(),
            textBoxBackupDbUser.Text.Trim(),
            textBoxBackupDbPassword.Text.Trim(),
            textBoxBackupDbName.Text.Trim(),
            labelBackupConnectionStatus
        );
    }
    
    // 测试导入数据库连接按钮点击事件
    private void ButtonTestImportConnection_Click(object sender, EventArgs e)
    {
        TestDatabaseConnection(
            textBoxImportDbHost.Text.Trim(),
            textBoxImportDbPort.Text.Trim(),
            textBoxImportDbUser.Text.Trim(),
            textBoxImportDbPassword.Text.Trim(),
            textBoxImportDbName.Text.Trim(),
            labelImportConnectionStatus
        );
    }
    
    // 通用的数据库连接测试方法
    private void TestDatabaseConnection(string host, string port, string user, string password, string dbName, Label statusLabel)
    {
        try
        {
            if (string.IsNullOrEmpty(host) || string.IsNullOrEmpty(port) || 
                string.IsNullOrEmpty(user) || string.IsNullOrEmpty(dbName))
            {
                statusLabel.ForeColor = Color.Red;
                statusLabel.Text = "请填写完整的数据库信息";
                MessageBox.Show("请填写完整的数据库信息！", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            
            statusLabel.ForeColor = Color.Blue;
            statusLabel.Text = "正在连接...";
            Application.DoEvents();
            
            // 直接启动 mysql.exe，避免外壳解释
            string mysqlExeVal = "mysql.exe";
            string[] possiblePaths = { "mysql.exe", "C:\\Program Files\\MySQL\\MySQL Server 8.0\\bin\\mysql.exe", "D:\\MySQL\\MySQL Server 8.0\\bin\\mysql.exe", "E:\\MySQL\\MySQL Server 8.0\\bin\\mysql.exe" };
            foreach (string p in possiblePaths)
            {
                if (File.Exists(p)) { mysqlExeVal = p; break; }
            }

            // Win32 命令行参数转义：将含空格/引号的参数正确包装（兼容 .NET Framework 4.8）
            System.Func<string, string> escapeArg = delegate(string arg)
            {
                if (string.IsNullOrEmpty(arg)) return "\"\"";
                bool needQuote = arg.IndexOfAny(new char[] { ' ', '\t', '\n', '"' }) >= 0;
                System.Text.StringBuilder sb = new System.Text.StringBuilder(arg.Length + 8);
                if (needQuote) sb.Append('"');
                int backslashes = 0;
                foreach (char c in arg)
                {
                    if (c == '\\') { backslashes++; }
                    else if (c == '"')
                    {
                        sb.Append('\\', backslashes * 2 + 1);
                        sb.Append('"');
                        backslashes = 0;
                    }
                    else
                    {
                        sb.Append('\\', backslashes);
                        sb.Append(c);
                        backslashes = 0;
                    }
                }
                sb.Append('\\', backslashes * 2);
                if (needQuote) sb.Append('"');
                return sb.ToString();
            };

            // 将每个参数用空格连接，mysql.exe 直接解析，不经过外壳
            string[] mysqlArgs = new string[] {
                "--host=" + host,
                "--port=" + port,
                "--user=" + user,
                "--password=" + password,
                "--default-character-set=utf8mb4",
                "-e",
                "SELECT 1",
                dbName
            };

            using (System.Diagnostics.Process process = new System.Diagnostics.Process())
            {
                System.Diagnostics.ProcessStartInfo psi = process.StartInfo;
                psi.FileName = mysqlExeVal;
                psi.Arguments = string.Join(" ", System.Array.ConvertAll(mysqlArgs, a => escapeArg(a)));
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;
                psi.StandardOutputEncoding = System.Text.Encoding.UTF8;
                psi.StandardErrorEncoding = System.Text.Encoding.UTF8;

                process.Start();
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();

                if (process.ExitCode == 0)
                {
                    statusLabel.ForeColor = Color.Green;
                    statusLabel.Text = "连接成功";
                    MessageBox.Show("✓ 连接成功！数据库可正常访问", "连接状态", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    statusLabel.ForeColor = Color.Red;
                    statusLabel.Text = "连接失败";
                    string errorMsg = string.IsNullOrEmpty(error) ? "无法连接到数据库" : error.Trim();
                    MessageBox.Show("✗ 连接失败：\n" + errorMsg, "连接状态", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
        catch (Exception ex)
        {
            statusLabel.ForeColor = Color.Red;
            statusLabel.Text = "发生错误";
            MessageBox.Show("✗ 发生错误：\n" + ex.Message, "异常", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
    
    // 保存备份数据库配置按钮点击事件
    private void ButtonSaveBackupDbConfig_Click(object sender, EventArgs e)
    {
        SaveDatabaseConfig(
            textBoxBackupDbHost.Text.Trim(),
            textBoxBackupDbPort.Text.Trim(),
            textBoxBackupDbUser.Text.Trim(),
            textBoxBackupDbPassword.Text.Trim(),
            textBoxBackupDbName.Text.Trim(),
            "backupMysql",
            "备份",
            labelBackupConnectionStatus
        );
    }
    
    // 保存导入数据库配置按钮点击事件
    private void ButtonSaveImportDbConfig_Click(object sender, EventArgs e)
    {
        SaveDatabaseConfig(
            textBoxImportDbHost.Text.Trim(),
            textBoxImportDbPort.Text.Trim(),
            textBoxImportDbUser.Text.Trim(),
            textBoxImportDbPassword.Text.Trim(),
            textBoxImportDbName.Text.Trim(),
            "importMysql",
            "导入",
            labelImportConnectionStatus
        );
    }
    
    // 通用的保存数据库配置方法
    private void SaveDatabaseConfig(string host, string port, string user, string password, string dbName, string sectionName, string configType, Label statusLabel)
    {
        try
        {
            if (string.IsNullOrEmpty(host) || string.IsNullOrEmpty(port) || 
                string.IsNullOrEmpty(user) || string.IsNullOrEmpty(dbName))
            {
                MessageBox.Show("请填写完整的数据库信息", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            
            // 保存到 config.json
            string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.json");
            if (!File.Exists(configPath))
            {
                MessageBox.Show("配置文件不存在", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            
            string jsonContent = File.ReadAllText(configPath, Encoding.UTF8);
            Newtonsoft.Json.Linq.JObject config = Newtonsoft.Json.Linq.JObject.Parse(jsonContent);
            
            // 创建或更新配置节
            Newtonsoft.Json.Linq.JObject dbSection = new Newtonsoft.Json.Linq.JObject();
            dbSection["host"] = host;
            dbSection["port"] = port;
            dbSection["user"] = user;
            dbSection["password"] = password;
            dbSection["database"] = dbName;
            
            config[sectionName] = dbSection;
            
            File.WriteAllText(configPath, config.ToString(Newtonsoft.Json.Formatting.Indented), Encoding.UTF8);
            
            statusLabel.ForeColor = Color.Green;
            statusLabel.Text = "✓ 配置已保存";
            MessageBox.Show(string.Format("{0}数据库配置已保存成功！", configType), "成功", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            statusLabel.ForeColor = Color.Red;
            statusLabel.Text = "✗ 保存失败：" + ex.Message;
            MessageBox.Show("保存配置时发生错误：" + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}

