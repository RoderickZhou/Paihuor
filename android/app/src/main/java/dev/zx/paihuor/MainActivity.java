package dev.zx.paihuor;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.app.TimePickerDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.provider.MediaStore;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.PopupMenu;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.integration.android.IntentIntegrator;
import com.google.zxing.integration.android.IntentResult;
import com.journeyapps.barcodescanner.BarcodeEncoder;

public final class MainActivity extends Activity implements TaskAdapter.Listener {
    private static final int PICK_IMAGES = 3001;
    private static final int RECORD_AUDIO = 3002;
    private static final int BG = 0xFFF3F6FF;
    private static final int TEXT = 0xFF17181C;
    private static final int SECONDARY = 0xFF9AA2B3;
    private static final int PRIMARY = 0xFF477CFF;

    private FrameLayout root;
    private TextView titleView;
    private ListView listView;
    private LinearLayout emptyView;
    private ImageView emptyIcon;
    private TextView emptyTitle;
    private TextView emptySubtitle;
    private ImageButton inboxButton;
    private ImageButton archiveButton;
    private TaskAdapter adapter;
    private boolean archive;
    private RelayClient relay;
    private long draftDeadline;
    private final List<PendingImage> pendingImages = new ArrayList<>();
    private LinearLayout imagePreviewRow;
    private MandarinSpeech speech;
    private VoiceInput voiceInput;
    private EditText pairingFamily;
    private RadioButton pairingHusband;
    private RadioButton pairingWife;
    private TaskRepository.Direction direction = TaskRepository.Direction.ALL;
    private final List<Button> directionButtons = new ArrayList<>();

    private final BroadcastReceiver syncedReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { refreshList(); }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);
        relay = new RelayClient(this);
        requestNotificationPermission();
        registerReceiver(syncedReceiver, new IntentFilter("dev.zx.paihuor.SYNCED"),
                Build.VERSION.SDK_INT >= 33 ? Context.RECEIVER_NOT_EXPORTED : 0);
        if (Profile.isComplete(this)) showMain(); else showPairing();
    }

    @Override protected void onDestroy() {
        if (voiceInput != null) voiceInput.close();
        if (speech != null) speech.close();
        unregisterReceiver(syncedReceiver);
        super.onDestroy();
    }

    @Override protected void onPause() {
        if (voiceInput != null) voiceInput.cancelRecording();
        super.onPause();
    }

    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(request, permissions, grants);
        if (request == RECORD_AUDIO && voiceInput != null) {
            voiceInput.message(grants.length > 0 && grants[0] == PackageManager.PERMISSION_GRANTED
                    ? "已允许麦克风，请重新按住说话" : "需要麦克风权限，也可手动填写");
        }
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 10);
        }
    }

    private void showPairing() {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(28), dp(38), dp(28), dp(28));
        page.setBackgroundColor(BG);
        page.addView(label("家庭配对", 34, TEXT, true));
        EditText family = input("例如 fam-zx-001");
        pairingFamily = family;
        family.setSingleLine(true);
        family.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        family.setText(Profile.familyId(this));
        family.setOnFocusChangeListener((view, focused) -> { if (focused) family.selectAll(); });
        page.addView(section("家庭码"));
        page.addView(family, match(dp(54)));

        page.addView(space(22));
        page.addView(section("我的身份"));
        RadioGroup roles = new RadioGroup(this);
        roles.setOrientation(LinearLayout.HORIZONTAL);
        RadioButton husband = new RadioButton(this);
        pairingHusband = husband;
        husband.setId(View.generateViewId());
        husband.setText("老公");
        husband.setTextSize(18);
        husband.setChecked(true);
        RadioButton wife = new RadioButton(this);
        pairingWife = wife;
        wife.setId(View.generateViewId());
        wife.setText("老婆");
        wife.setTextSize(18);
        roles.addView(husband, new LinearLayout.LayoutParams(0, dp(54), 1));
        roles.addView(wife, new LinearLayout.LayoutParams(0, dp(54), 1));
        roles.check("wife".equals(Profile.userId(this)) ? wife.getId() : husband.getId());
        page.addView(roles);

        page.addView(space(18));
        page.addView(section("显示名称"));
        EditText name = input("老公");
        if (Profile.isComplete(this)) name.setText(Profile.userName(this));
        page.addView(name, match(dp(54)));

        LinearLayout pairActions = new LinearLayout(this);
        Button scan = new Button(this);
        scan.setText("扫码配对");
        scan.setOnClickListener(view -> new IntentIntegrator(this).setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                .setPrompt("扫描派活儿家庭二维码").setBeepEnabled(false).initiateScan());
        pairActions.addView(scan, weighted());
        if (Profile.isComplete(this)) {
            Button qr = new Button(this);
            qr.setText("家庭二维码");
            qr.setOnClickListener(view -> showPairingCode());
            pairActions.addView(qr, weighted());
        }
        page.addView(pairActions, match(dp(52)));

        Button enter = new Button(this);
        enter.setText("保存配对");
        enter.setTextColor(Color.WHITE);
        enter.setTextSize(17);
        enter.setBackground(round(PRIMARY, 27));
        LinearLayout.LayoutParams enterParams = match(dp(56));
        enterParams.topMargin = dp(34);
        page.addView(enter, enterParams);
        enter.setOnClickListener(view -> {
            String familyId = family.getText().toString().trim();
            if (familyId.isEmpty() || familyId.length() > 120) { family.setError("请填写有效的家庭码"); return; }
            String role = wife.isChecked() ? "wife" : "husband";
            String display = name.getText().toString().trim();
            if (display.isEmpty()) display = wife.isChecked() ? "老婆" : "老公";
            Profile.save(this, familyId, role, display);
            showMain();
        });
        roles.setOnCheckedChangeListener((group, checkedId) ->
                name.setHint(wife.isChecked() ? "老婆" : "老公"));
        if (Profile.isComplete(this)) {
            Button cancel = new Button(this);
            cancel.setText("取消");
            cancel.setOnClickListener(view -> showMain());
            page.addView(cancel, match(dp(48)));
            TextView health = label("正在检查同步…", 14, TEXT, false);
            health.setPadding(0, dp(10), 0, 0);
            page.addView(health, matchWrap());
            String savedFamily = Profile.familyId(this), savedRole = Profile.userId(this);
            new Thread(() -> {
                String result;
                try {
                    JSONObject value = relay.syncStatus(savedFamily, savedRole);
                    result = "本机同步：" + syncTime(value.optLong("selfSyncedAt"))
                            + "\n对方同步：" + syncTime(value.optLong("peerSyncedAt"))
                            + "\n本机通知：" + (getSystemService(android.app.NotificationManager.class).areNotificationsEnabled() ? "后台轮询，通知已开启" : "系统通知未开启");
                } catch (Exception error) { result = "无法检查中继连接"; }
                String status = result;
                runOnUiThread(() -> health.setText(status));
            }, "pairing-status").start();
        }
        ScrollView scroll = new ScrollView(this);
        scroll.addView(page);
        page.setFocusableInTouchMode(true);
        setContentView(scroll);
        page.requestFocus();
    }

    private static String syncTime(long time) {
        return time == 0 ? "暂无记录" : new SimpleDateFormat("MM-dd HH:mm", Locale.CHINA).format(new Date(time));
    }

    private void showPairingCode() {
        try {
            String family = Uri.encode(Profile.familyId(this));
            String code = "paihuor:pair:1:" + Profile.counterpart(this) + ":" + family;
            ImageView qr = new ImageView(this);
            qr.setImageBitmap(new BarcodeEncoder().encodeBitmap(code, BarcodeFormat.QR_CODE, dp(240), dp(240)));
            qr.setAdjustViewBounds(true);
            new AlertDialog.Builder(this).setTitle("家庭二维码").setView(qr).setPositiveButton("关闭", null).show();
        } catch (Exception error) { toast("二维码生成失败"); }
    }

    private void showMain() {
        pairingFamily = null;
        root = new FrameLayout(this);
        root.setBackgroundColor(BG);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.addView(header(), match(dp(82)));
        LinearLayout filters = new LinearLayout(this);
        filters.setPadding(dp(18), 0, dp(18), dp(4));
        directionButtons.clear();
        String[] labels = {"全部", "派给我", "我派出"};
        for (TaskRepository.Direction value : TaskRepository.Direction.values()) {
            Button filter = new Button(this);
            filter.setText(labels[value.ordinal()]);
            filter.setTextSize(14);
            filter.setMinHeight(0);
            filter.setOnClickListener(view -> { direction = value; refreshList(); });
            directionButtons.add(filter);
            filters.addView(filter, weighted());
        }
        content.addView(filters, match(dp(44)));

        FrameLayout body = new FrameLayout(this);
        listView = new ListView(this);
        listView.setDivider(new ColorDrawable(Color.TRANSPARENT));
        listView.setDividerHeight(0);
        listView.setSelector(new ColorDrawable(Color.TRANSPARENT));
        listView.setClipToPadding(false);
        listView.setPadding(0, 0, 0, dp(130));
        adapter = new TaskAdapter(this, Profile.userId(this), this);
        listView.setAdapter(adapter);
        body.addView(listView, frameMatch());

        emptyView = new LinearLayout(this);
        emptyView.setOrientation(LinearLayout.VERTICAL);
        emptyView.setGravity(Gravity.CENTER);
        emptyIcon = new ImageView(this);
        emptyView.addView(emptyIcon, new LinearLayout.LayoutParams(dp(120), dp(120)));
        emptyTitle = label("没有任务", 24, TEXT, true);
        emptyTitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams emptyTitleParams = matchWrap();
        emptyTitleParams.topMargin = dp(20);
        emptyView.addView(emptyTitle, emptyTitleParams);
        emptySubtitle = label("点击 + 按钮即可添加", 17, SECONDARY, false);
        emptySubtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams emptySubtitleParams = matchWrap();
        emptySubtitleParams.topMargin = dp(8);
        emptyView.addView(emptySubtitle, emptySubtitleParams);
        body.addView(emptyView, frameMatch());
        content.addView(body, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        root.addView(content, frameMatch());
        root.addView(fab(), fabParams());
        root.addView(dock(), dockParams());
        setContentView(root);

        refreshList();
        syncNow(false);
        startForegroundService(new Intent(this, PollService.class));
    }

    private View header() {
        FrameLayout header = new FrameLayout(this);
        ImageButton menu = iconButton(R.drawable.icon_menu, R.drawable.circle_white);
        FrameLayout.LayoutParams menuParams = new FrameLayout.LayoutParams(dp(52), dp(52), Gravity.START | Gravity.CENTER_VERTICAL);
        menuParams.leftMargin = dp(24);
        header.addView(menu, menuParams);
        menu.setOnClickListener(this::showMenu);

        titleView = label(archive ? "归档" : "收集箱", 28, TEXT, true);
        FrameLayout.LayoutParams titleParams = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.START | Gravity.CENTER_VERTICAL);
        titleParams.leftMargin = dp(90);
        header.addView(titleView, titleParams);

        ImageButton grid = iconButton(R.drawable.icon_grid, R.drawable.circle_white);
        FrameLayout.LayoutParams gridParams = new FrameLayout.LayoutParams(dp(52), dp(52), Gravity.END | Gravity.CENTER_VERTICAL);
        gridParams.rightMargin = dp(24);
        header.addView(grid, gridParams);
        return header;
    }

    private View dock() {
        LinearLayout dock = new LinearLayout(this);
        dock.setGravity(Gravity.CENTER);
        dock.setBackgroundResource(R.drawable.dock_background);
        dock.setElevation(dp(10));
        inboxButton = dockButton(R.drawable.icon_inbox_active);
        inboxButton.setBackgroundResource(R.drawable.dock_active_background);
        archiveButton = dockButton(R.drawable.icon_archive);
        ImageButton refresh = dockButton(R.drawable.icon_refresh);
        dock.addView(inboxButton, weighted());
        dock.addView(archiveButton, weighted());
        dock.addView(refresh, weighted());
        inboxButton.setOnClickListener(view -> switchBoard(false));
        archiveButton.setOnClickListener(view -> switchBoard(true));
        refresh.setOnClickListener(view -> syncNow(true));
        return dock;
    }

    private View fab() {
        TextView button = label("+", 39, Color.WHITE, false);
        button.setGravity(Gravity.CENTER);
        button.setBackgroundResource(R.drawable.circle_primary);
        button.setElevation(dp(12));
        button.setOnClickListener(view -> showCreateDialog());
        return button;
    }

    private void switchBoard(boolean archive) {
        this.archive = archive;
        titleView.setText(archive ? "归档" : "收集箱");
        inboxButton.setImageResource(archive ? R.drawable.icon_inbox : R.drawable.icon_inbox_active);
        archiveButton.setImageResource(archive ? R.drawable.icon_archive_active : R.drawable.icon_archive);
        inboxButton.setBackgroundResource(archive ? android.R.color.transparent : R.drawable.dock_active_background);
        archiveButton.setBackgroundResource(archive ? R.drawable.dock_active_background : android.R.color.transparent);
        refreshList();
    }

    private void refreshList() {
        if (adapter == null || !Profile.isComplete(this)) return;
        long now = System.currentTimeMillis(), tomorrow = TaskRepository.tomorrow(now);
        List<TaskItem> visible = TaskRepository.visible(TaskCache.load(this), Profile.familyId(this),
                Profile.userId(this), archive, direction, now, tomorrow);
        for (int i = 0; i < directionButtons.size(); i++) {
            Button filter = directionButtons.get(i);
            boolean selected = i == direction.ordinal();
            filter.setSelected(selected);
            filter.setTextColor(selected ? PRIMARY : TEXT);
            filter.setBackground(round(selected ? 0xFFDDE6FF : Color.TRANSPARENT, 8));
        }
        adapter.setItems(visible, archive, now, tomorrow);
        boolean empty = visible.isEmpty();
        emptyView.setVisibility(empty ? View.VISIBLE : View.GONE);
        listView.setVisibility(empty ? View.GONE : View.VISIBLE);
        emptyIcon.setImageResource(archive ? R.drawable.icon_empty_archive : R.drawable.icon_empty_inbox);
        emptyTitle.setText(direction == TaskRepository.Direction.ALL ? (archive ? "归档里还没有记录" : "没有任务") : "这个筛选下没有任务");
        emptySubtitle.setText(direction == TaskRepository.Direction.ALL ? (archive ? "完成后的任务会收进这里" : "点击 + 按钮即可添加") : "");
    }

    private void syncNow(boolean notify) {
        String family = Profile.familyId(this);
        new Thread(() -> {
            try {
                JSONArray tasks = relay.fetch(family, 0);
                TaskCache.merge(this, tasks);
                startForegroundService(new Intent(this, PollService.class));
                runOnUiThread(() -> { refreshList(); if (notify) toast("已同步"); });
            } catch (Exception error) {
                if (notify) runOnUiThread(() -> toast("同步失败：" + error.getMessage()));
            }
        }).start();
    }

    private void showMenu(View anchor) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.getMenu().add("家庭设置");
        menu.getMenu().add("立即同步");
        menu.getMenu().add("复制上次");
        menu.setOnMenuItemClickListener(item -> {
            if ("家庭设置".contentEquals(item.getTitle())) showPairing();
            else if ("复制上次".contentEquals(item.getTitle())) copyLast();
            else syncNow(true);
            return true;
        });
        menu.show();
    }

    private void copyLast() {
        TaskItem last = TaskCache.load(this).stream().filter(task -> !task.deleted && !task.queued && !task.repeatGenerated
                && task.familyId.equals(Profile.familyId(this)) && task.fromUserId.equals(Profile.userId(this)))
                .max(java.util.Comparator.comparingLong(task -> task.createdAt)).orElse(null);
        if (last == null) toast("还没有派出的任务"); else showCreateDialog(last);
    }

    private void showCreateDialog() {
        showCreateDialog(null);
    }

    private void showCreateDialog(TaskItem copied) {
        pendingImages.clear();
        draftDeadline = 0;
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(24), dp(18), dp(24), dp(24));
        form.addView(label("派一件活", 25, TEXT, true));
        String recipient = "wife".equals(Profile.counterpart(this)) ? "老婆" : "老公";
        TextView recipientLabel = label("接收人：" + recipient, 15, TEXT, true);
        recipientLabel.setPadding(0, dp(10), 0, 0);
        form.addView(recipientLabel, matchWrap());
        Button record = new Button(this);
        record.setTextColor(Color.WHITE);
        record.setTextSize(16);
        Drawable mic = getDrawable(R.drawable.icon_mic);
        mic.setBounds(0, 0, dp(20), dp(20));
        record.setCompoundDrawablesRelative(mic, null, null, null);
        record.setPadding(dp(18), 0, dp(18), 0);
        LinearLayout.LayoutParams recordParams = match(dp(52)); recordParams.topMargin = dp(14);
        form.addView(record, recordParams);
        TextView voiceMessage = label("", 14, 0xFF596274, false);
        voiceMessage.setMaxLines(3);
        voiceMessage.setEllipsize(android.text.TextUtils.TruncateAt.END);
        voiceMessage.setPadding(0, dp(8), 0, 0);
        voiceMessage.setVisibility(View.GONE);
        form.addView(voiceMessage, matchWrap());
        EditText title = input("要做什么？");
        if (copied != null) title.setText(copied.title.isEmpty() ? copied.rawText : copied.title);
        LinearLayout.LayoutParams titleParams = match(dp(56)); titleParams.topMargin = dp(18);
        form.addView(title, titleParams);
        EditText detail = input("补充细节（可选）");
        if (copied != null) detail.setText(copied.detail);
        LinearLayout.LayoutParams detailParams = match(dp(70)); detailParams.topMargin = dp(10);
        form.addView(detail, detailParams);

        TextView deadline = label("截止时间：未设置", 15, TEXT, false);
        deadline.setPadding(dp(12), dp(15), dp(12), dp(15));
        deadline.setBackground(round(0xFFF1F4FB, 8));
        LinearLayout.LayoutParams deadlineParams = matchWrap(); deadlineParams.topMargin = dp(10);
        form.addView(deadline, deadlineParams);
        deadline.setOnClickListener(view -> {
            if (draftDeadline == 0) pickDeadline(deadline);
            else new AlertDialog.Builder(this).setItems(new String[]{"修改截止时间", "清除截止时间"}, (picker, choice) -> {
                if (choice == 0) pickDeadline(deadline);
                else { draftDeadline = 0; updateDraftDeadline(deadline); }
            }).show();
        });

        String[] repeatKind = {""};
        int[] repeatDays = {7};
        Button repeat = new Button(this);
        repeat.setText("重复：不重复");
        repeat.setOnClickListener(view -> new AlertDialog.Builder(this).setTitle("重复规则")
                .setItems(new String[]{"不重复", "每周", "每月", "完成后隔 N 天"}, (rules, index) -> {
                    if (index == 3) {
                        EditText days = input("1–365 天");
                        days.setInputType(InputType.TYPE_CLASS_NUMBER);
                        days.setText(String.valueOf(repeatDays[0]));
                        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("完成后隔几天")
                                .setView(days).setNegativeButton("取消", null).setPositiveButton("确定", null).show();
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(confirm -> {
                            int value;
                            try { value = Integer.parseInt(days.getText().toString()); }
                            catch (NumberFormatException ignored) { value = 0; }
                            if (value < 1 || value > 365) { days.setError("请输入 1 到 365"); return; }
                            repeatKind[0] = "afterDone";
                            repeatDays[0] = value;
                            repeat.setText("重复：" + TaskRepository.repeatLabel(repeatKind[0], value));
                            dialog.dismiss();
                        });
                    } else {
                        repeatKind[0] = new String[]{"", "weekly", "monthly"}[index];
                        repeat.setText("重复：" + TaskRepository.repeatLabel(repeatKind[0], repeatDays[0]));
                    }
                }).show());
        form.addView(repeat, match(dp(46)));

        LinearLayout imageHeader = new LinearLayout(this);
        imageHeader.setGravity(Gravity.CENTER_VERTICAL);
        TextView imageLabel = label("图片", 16, TEXT, true);
        imageHeader.addView(imageLabel, new LinearLayout.LayoutParams(0, dp(48), 1));
        Button addImage = new Button(this);
        addImage.setText("＋ 添加");
        addImage.setOnClickListener(view -> pickImages());
        imageHeader.addView(addImage, new LinearLayout.LayoutParams(dp(110), dp(48)));
        form.addView(imageHeader);
        HorizontalScrollView imageScroll = new HorizontalScrollView(this);
        imagePreviewRow = new LinearLayout(this);
        imagePreviewRow.setOrientation(LinearLayout.HORIZONTAL);
        imageScroll.addView(imagePreviewRow);
        form.addView(imageScroll, match(dp(92)));

        Button send = new Button(this);
        send.setText("发送给" + recipient);
        send.setTextColor(Color.WHITE);
        send.setTextSize(17);
        send.setBackground(round(PRIMARY, 27));
        LinearLayout.LayoutParams sendParams = match(dp(56)); sendParams.topMargin = dp(12);
        form.addView(send, sendParams);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(form);
        AlertDialog dialog = bottomDialog(scroll);
        if (speech == null) speech = new MandarinSpeech(this);
        VoiceInput voice = new VoiceInput(record, voiceMessage, title, detail, deadline, send);
        voiceInput = voice;
        dialog.setOnDismissListener(ignored -> {
            voice.close();
            if (voiceInput == voice) voiceInput = null;
        });
        send.setOnClickListener(view -> {
            String value = title.getText().toString().trim();
            if (value.isEmpty()) { title.setError("请输入任务"); return; }
            if ((repeatKind[0].equals("weekly") || repeatKind[0].equals("monthly")) && draftDeadline <= System.currentTimeMillis()) {
                toast("请为第一次设定未来的截止时间");
                return;
            }
            send.setEnabled(false);
            record.setEnabled(false);
            createTask(value, detail.getText().toString().trim(), voice.transcript, draftDeadline, repeatKind[0], repeatDays[0],
                    new ArrayList<>(pendingImages), dialog);
        });
        dialog.show();
        styleBottom(dialog);
        dialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN
                | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        form.setFocusableInTouchMode(true);
        form.requestFocus();
        voice.prepare();
    }

    private final class VoiceInput {
        private final Button record;
        private final TextView status;
        private final EditText title;
        private final EditText detail;
        private final TextView deadline;
        private final Button send;
        private final Runnable hold = this::start;
        private final Runnable resultTimeout = this::fail;
        private boolean ready;
        private boolean recording;
        private boolean busy;
        private boolean closed;
        private String transcript = "";

        VoiceInput(Button record, TextView status, EditText title, EditText detail, TextView deadline, Button send) {
            this.record = record;
            this.status = status;
            this.title = title;
            this.detail = detail;
            this.deadline = deadline;
            this.send = send;
            record.setOnClickListener(view -> {
                if (!busy && !recording) message("请按住说话，松开后生成草稿");
            });
            record.setOnTouchListener((view, event) -> {
                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        view.getParent().requestDisallowInterceptTouchEvent(true);
                        view.postDelayed(hold, 150);
                        return true;
                    case MotionEvent.ACTION_UP:
                        view.removeCallbacks(hold);
                        if (recording) finish(); else if (ready && !busy) view.performClick();
                        view.getParent().requestDisallowInterceptTouchEvent(false);
                        return true;
                    case MotionEvent.ACTION_CANCEL:
                        cancelRecording();
                        view.getParent().requestDisallowInterceptTouchEvent(false);
                        return true;
                    default: return true;
                }
            });
        }

        void prepare() {
            updateControls();
            speech.prepare(success -> {
                if (closed) return;
                ready = success;
                updateControls();
                if (!success) {
                    record.setText("语音暂不可用");
                    message("语音识别初始化失败，可手动填写");
                }
            });
        }

        void message(String value) {
            status.setText(value);
            status.setVisibility(value.isEmpty() ? View.GONE : View.VISIBLE);
        }

        private void updateControls() {
            record.setText(recording ? "松开生成草稿" : busy ? "正在生成草稿…" : ready ? "按住说话" : "正在准备语音…");
            record.setBackground(round(recording ? 0xFFB43D45 : PRIMARY, 26));
            record.setEnabled(ready && !busy);
            send.setEnabled(!recording && !busy);
            title.setEnabled(!recording && !busy);
            detail.setEnabled(!recording && !busy);
            deadline.setEnabled(!recording && !busy);
        }

        private void start() {
            if (closed || !ready || busy || recording) return;
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, RECORD_AUDIO);
                return;
            }
            recording = true;
            updateControls();
            message("正在听…");
            speech.start(value -> { if (!value.isEmpty()) message(value); }, this::complete, this::fail);
        }

        private void fail() {
            record.removeCallbacks(resultTimeout);
            if (closed || (!busy && !recording)) return;
            speech.cancel();
            recording = false;
            busy = false;
            updateControls();
            message("语音识别未完成，请重试或手动填写");
        }

        private void finish() {
            recording = false;
            busy = true;
            updateControls();
            record.postDelayed(resultTimeout, 10000);
            speech.finish();
        }

        private void complete(String value) {
            if (closed || !busy) return;
            record.removeCallbacks(resultTimeout);
            if (value.isEmpty()) {
                busy = false;
                updateControls();
                message("没听清，请再说一次或手动填写");
                return;
            }
            message(value);
            new Thread(() -> {
                VoiceDraft result;
                try { result = VoiceTaskParser.extract(Config.load(MainActivity.this), value); }
                catch (Exception ignored) { result = null; }
                VoiceDraft draft = result;
                runOnUiThread(() -> {
                    if (closed) return;
                    transcript = value;
                    busy = false;
                    title.setText(draft == null ? value : draft.title);
                    detail.setText(draft == null ? "" : draft.detail);
                    draftDeadline = draft == null ? 0 : draft.deadline;
                    updateDraftDeadline(deadline);
                    message(draft == null ? "未能自动整理，已填入原话，请手动确认" : value);
                    updateControls();
                });
            }, "voice-draft").start();
        }

        void cancelRecording() {
            record.removeCallbacks(hold);
            if (!recording) return;
            speech.cancel();
            recording = false;
            message("录音已取消");
            updateControls();
        }

        void close() {
            if (closed) return;
            closed = true;
            record.removeCallbacks(hold);
            record.removeCallbacks(resultTimeout);
            speech.cancel();
        }
    }

    private void createTask(String title, String detail, String transcript, long deadline, String repeatKind, int repeatDays,
                            List<PendingImage> images, AlertDialog dialog) {
        String family = Profile.familyId(this), role = Profile.userId(this), peer = Profile.counterpart(this);
        new Thread(() -> {
            try {
                TaskItem task = new TaskItem();
                task.objectId = UUID.randomUUID().toString();
                task.clientRequestId = task.objectId;
                task.queued = true;
                task.createdAt = System.currentTimeMillis();
                task.familyId = family;
                task.fromUserId = role;
                task.toUserId = peer;
                task.rawText = transcript.isEmpty() ? title : transcript;
                task.title = title;
                task.detail = detail;
                task.deadline = deadline;
                task.repeatKind = repeatKind;
                task.repeatDays = repeatDays;
                task.status = "pending";
                for (PendingImage pending : images) {
                    TaskItem.TaskImage image = new TaskItem.TaskImage();
                    image.id = "local-" + task.images.size();
                    image.width = pending.width;
                    image.height = pending.height;
                    java.nio.file.Files.write(TaskOutbox.attachment(this, task, task.images.size()).toPath(), pending.bytes);
                    task.images.add(image);
                }
                TaskCache.upsert(this, task);
                runOnUiThread(() -> {
                    dialog.dismiss();
                    if (direction == TaskRepository.Direction.INCOMING) direction = TaskRepository.Direction.OUTGOING;
                    switchBoard(false);
                    startForegroundService(new Intent(this, PollService.class));
                    toast("已加入待发送");
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (dialog.isShowing() && voiceInput != null) voiceInput.updateControls();
                    toast("发送失败：" + error.getMessage());
                });
            }
        }).start();
    }

    private void pickDeadline(TextView view) {
        chooseDeadline(draftDeadline, selected -> {
            draftDeadline = selected;
            updateDraftDeadline(view);
        });
    }

    private void chooseDeadline(long initial, java.util.function.LongConsumer apply) {
        Calendar calendar = Calendar.getInstance();
        if (initial > 0) calendar.setTimeInMillis(initial);
        DatePickerDialog date = new DatePickerDialog(this, (picker, year, month, day) -> {
            TimePickerDialog time = new TimePickerDialog(this, (timePicker, hour, minute) -> {
                Calendar result = Calendar.getInstance();
                result.clear();
                result.set(year, month, day, hour, minute, 0);
                apply.accept(result.getTimeInMillis());
            }, calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE), true);
            time.show();
        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH));
        date.show();
    }

    private void updateDraftDeadline(TextView view) {
        view.setText("截止时间：" + (draftDeadline == 0 ? "未设置"
                : new SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA).format(new Date(draftDeadline))));
    }

    private void pickImages() {
        Intent intent;
        if (Build.VERSION.SDK_INT >= 33) {
            intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
            intent.setType("image/*");
        } else {
            intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.setType("image/*");
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        }
        startActivityForResult(intent, PICK_IMAGES);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        IntentResult scanned = IntentIntegrator.parseActivityResult(requestCode, resultCode, data);
        if (scanned != null) {
            String value = scanned.getContents();
            if (value != null && pairingFamily != null) {
                String[] fields = value.split(":", 5);
                if (fields.length != 5 || !value.startsWith("paihuor:pair:1:") || !fields[3].matches("wife|husband")) {
                    toast("这不是派活儿家庭二维码");
                    return;
                }
                String family = Uri.decode(fields[4]).trim();
                if (family.isEmpty() || family.length() > 120) { toast("家庭码无效"); return; }
                pairingFamily.setText(family);
                if (fields[3].equals("wife")) pairingWife.setChecked(true); else pairingHusband.setChecked(true);
                toast("请核对家庭码和身份后保存");
            }
            return;
        }
        if (requestCode != PICK_IMAGES || resultCode != RESULT_OK || data == null) return;
        List<Uri> uris = new ArrayList<>();
        if (data.getClipData() != null) {
            for (int index = 0; index < data.getClipData().getItemCount(); index++)
                uris.add(data.getClipData().getItemAt(index).getUri());
        } else if (data.getData() != null) uris.add(data.getData());
        new Thread(() -> {
            for (Uri uri : uris) {
                if (pendingImages.size() >= 9) break;
                PendingImage image = prepareImage(uri);
                if (image != null) pendingImages.add(image);
            }
            runOnUiThread(this::renderImagePreviews);
        }).start();
    }

    private PendingImage prepareImage(Uri uri) {
        try (InputStream input = getContentResolver().openInputStream(uri)) {
            Bitmap original = BitmapFactory.decodeStream(input);
            if (original == null) return null;
            float scale = Math.min(1f, 1600f / Math.max(original.getWidth(), original.getHeight()));
            int width = Math.max(1, Math.round(original.getWidth() * scale));
            int height = Math.max(1, Math.round(original.getHeight() * scale));
            Bitmap resized = scale < 1f ? Bitmap.createScaledBitmap(original, width, height, true) : original;
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            resized.compress(Bitmap.CompressFormat.JPEG, 80, output);
            return new PendingImage(output.toByteArray(), resized, width, height);
        } catch (Exception ignored) { return null; }
    }

    private void renderImagePreviews() {
        if (imagePreviewRow == null) return;
        imagePreviewRow.removeAllViews();
        for (PendingImage pending : pendingImages) {
            ImageView image = new ImageView(this);
            image.setImageBitmap(pending.preview);
            image.setScaleType(ImageView.ScaleType.CENTER_CROP);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(78), dp(78));
            params.rightMargin = dp(9);
            imagePreviewRow.addView(image, params);
        }
    }

    @Override public void onOpen(TaskItem item) {
        if (item.queued) {
            new AlertDialog.Builder(this).setTitle("待发送").setMessage(item.title)
                    .setPositiveButton("立即重试", (dialog, which) -> startForegroundService(new Intent(this, PollService.class)))
                    .setNegativeButton("关闭", null).show();
        } else showTaskDetail(item);
    }

    @Override
    public void onCheck(TaskItem item) {
        if (item.archived || !item.toUserId.equals(Profile.userId(this))) return;
        long now = System.currentTimeMillis();
        TaskRepository.advance(item, now);
        patchTask(item, json("status", item.status, "receivedAt", item.receivedAt,
                "doneAt", item.doneAt, "archived", item.archived));
    }

    @Override
    public void onMore(TaskItem item, View anchor) {
        if (item.queued) { onOpen(item); return; }
        PopupMenu menu = new PopupMenu(this, anchor);
        if (!item.archived && !"done".equals(item.status)) menu.getMenu().add("商量");
        menu.getMenu().add(item.archived ? "取消归档" : "归档");
        if (item.fromUserId.equals(Profile.userId(this))) {
            menu.getMenu().add("编辑");
            menu.getMenu().add("删除");
        }
        menu.setOnMenuItemClickListener(action -> {
            String title = action.getTitle().toString();
            if ("商量".equals(title)) showNegotiate(item);
            else if ("编辑".equals(title)) showEdit(item);
            else if ("删除".equals(title)) deleteTask(item);
            else patchTask(item, json("archived", "归档".equals(title)));
            return true;
        });
        menu.show();
    }

    private void showTaskDetail(TaskItem item) {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(24), dp(20), dp(24), dp(28));
        content.addView(label(item.title.isEmpty() ? item.rawText : item.title, 25, TEXT, true));
        if (!item.detail.isEmpty()) {
            TextView detail = label(item.detail, 16, SECONDARY, false);
            detail.setPadding(0, dp(12), 0, 0);
            content.addView(detail);
        }
        if (item.deadline > 0) {
            TextView deadline = label("截止  " + new SimpleDateFormat("yyyy年MM月dd日 HH:mm", Locale.CHINA)
                    .format(new Date(item.deadline)), 15, PRIMARY, true);
            deadline.setPadding(0, dp(14), 0, 0);
            content.addView(deadline);
        }
        if (!item.images.isEmpty()) content.addView(detailImages(item));
        String statusLabel = item.skippedAt > 0 ? "已跳过" : "done".equals(item.status) ? "已完成"
                : "received".equals(item.status) ? "已接下" : "negotiating".equals(item.status) ? "商量中" : "待接下";
        TextView status = label("状态  " + statusLabel, 15, SECONDARY, false);
        status.setPadding(0, dp(16), 0, dp(8));
        content.addView(status);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        AlertDialog dialog = bottomDialog(scroll);
        if (!item.repeatKind.isEmpty()) {
            Button rule = new Button(this);
            rule.setText("重复：" + TaskRepository.repeatLabel(item.repeatKind, item.repeatDays)
                    + (item.repeatCurrent && item.repeatPaused ? "（已暂停）" : ""));
            rule.setEnabled(item.repeatCurrent && (!"done".equals(item.status) || item.fromUserId.equals(Profile.userId(this))));
            rule.setOnClickListener(view -> showRepeatActions(item, dialog));
            content.addView(rule, match(dp(48)));
        }
        Button copy = new Button(this);
        copy.setText("复制为新任务");
        copy.setOnClickListener(view -> { dialog.dismiss(); showCreateDialog(item); });
        content.addView(copy, match(dp(48)));

        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        if (item.skippedAt > 0) {
            // Skipped occurrences remain in history and cannot be reopened.
        } else if (item.archived) {
            actions.addView(actionButton("取消归档", () -> patchTask(item, json("archived", false))));
        } else if ("done".equals(item.status)) {
            actions.addView(actionButton("归档", () -> patchTask(item, json("archived", true))));
        } else if (item.toUserId.equals(Profile.userId(this))) {
            String primary = "received".equals(item.status) ? "勾掉完成" : "收到";
            actions.addView(actionButton(primary, () -> onCheck(item)));
            actions.addView(actionButton("商量", () -> showNegotiate(item)));
        } else {
            actions.addView(actionButton("编辑", () -> showEdit(item)));
            actions.addView(actionButton("商量", () -> showNegotiate(item)));
        }
        if (item.fromUserId.equals(Profile.userId(this))) {
            TextView delete = label("删除", 14, 0xFFE84B4B, false);
            delete.setGravity(Gravity.CENTER);
            delete.setPadding(dp(14), dp(10), dp(14), dp(10));
            delete.setOnClickListener(view -> deleteTask(item));
            actions.addView(delete);
        }
        LinearLayout.LayoutParams actionParams = matchWrap();
        actionParams.topMargin = dp(12);
        content.addView(actions, actionParams);
        dialog.show();
        styleBottom(dialog);
    }

    private void showRepeatActions(TaskItem item, AlertDialog detail) {
        List<String> labels = new ArrayList<>(), actions = new ArrayList<>();
        if (!"done".equals(item.status)) { labels.add("跳过本次"); actions.add("skip"); }
        if (item.fromUserId.equals(Profile.userId(this))) {
            labels.add(item.repeatPaused ? "恢复重复" : "暂停重复");
            actions.add(item.repeatPaused ? "resume" : "pause");
        }
        if (labels.isEmpty()) return;
        new AlertDialog.Builder(this).setTitle("重复任务").setItems(labels.toArray(new String[0]), (menu, i) -> {
            String action = actions.get(i);
            new AlertDialog.Builder(this).setMessage(labels.get(i) + "？")
                    .setNegativeButton("取消", null).setPositiveButton("确定", (confirm, which) -> new Thread(() -> {
                        try {
                            TaskCache.upsert(this, relay.repeatAction(item, Profile.userId(this), action));
                            runOnUiThread(() -> { detail.dismiss(); refreshList(); syncNow(false); });
                        } catch (Exception error) { runOnUiThread(() -> toast("更新重复任务失败，请同步后重试")); }
                    }).start()).show();
        }).show();
    }

    private View detailImages(TaskItem item) {
        LinearLayout block = new LinearLayout(this);
        block.setOrientation(LinearLayout.VERTICAL);
        TextView label = label("图片 · " + item.images.size() + " 张", 15, TEXT, true);
        label.setPadding(0, dp(16), 0, dp(8));
        block.addView(label);
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        LinearLayout row = new LinearLayout(this);
        for (TaskItem.TaskImage attachment : item.images) {
            ImageView image = new ImageView(this);
            image.setBackgroundColor(0xFFDCE6FF);
            image.setScaleType(ImageView.ScaleType.CENTER_CROP);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(116), dp(116));
            params.rightMargin = dp(10);
            row.addView(image, params);
            new Thread(() -> {
                try {
                    byte[] bytes = relay.download(attachment.id);
                    Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                    runOnUiThread(() -> image.setImageBitmap(bitmap));
                } catch (Exception ignored) {}
            }).start();
        }
        scroll.addView(row);
        block.addView(scroll, match(dp(116)));
        return block;
    }

    private void showNegotiate(TaskItem item) {
        EditText input = input("说说想怎么调整");
        new AlertDialog.Builder(this).setTitle("商量一下").setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("发送", (dialog, which) -> {
                    String text = input.getText().toString().trim();
                    if (text.isEmpty()) return;
                    TaskItem.Negotiation message = new TaskItem.Negotiation();
                    message.fromUserId = Profile.userId(this);
                    message.text = text;
                    message.createdAt = System.currentTimeMillis();
                    item.negotiation.add(message);
                    patchTask(item, json("status", "negotiating", "negotiation",
                            TaskJson.encode(item).optJSONArray("negotiation")));
                }).show();
    }

    private void showEdit(TaskItem item) {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(24), dp(18), dp(24), dp(24));
        form.addView(label("编辑任务", 20, TEXT, true));
        EditText title = input("任务标题");
        title.setText(item.title);
        LinearLayout.LayoutParams titleParams = match(dp(56)); titleParams.topMargin = dp(16);
        form.addView(title, titleParams);
        EditText detail = input("补充细节");
        detail.setText(item.detail);
        LinearLayout.LayoutParams detailParams = match(dp(70)); detailParams.topMargin = dp(10);
        form.addView(detail, detailParams);
        long[] deadline = { item.deadline };
        Button due = new Button(this);
        due.setText(editDeadlineLabel(deadline[0]));
        due.setOnClickListener(view -> new AlertDialog.Builder(this).setItems(new String[]{"选择时间", "清除时间"}, (menu, choice) -> {
            if (choice == 0) chooseDeadline(deadline[0], selected -> { deadline[0] = selected; due.setText(editDeadlineLabel(selected)); });
            else { deadline[0] = 0; due.setText(editDeadlineLabel(0)); }
        }).show());
        form.addView(due, match(dp(48)));
        Button save = new Button(this);
        save.setText("保存");
        save.setTextColor(Color.WHITE);
        save.setBackground(round(PRIMARY, 25));
        LinearLayout.LayoutParams saveParams = match(dp(52)); saveParams.topMargin = dp(14);
        form.addView(save, saveParams);
        AlertDialog dialog = bottomDialog(form);
        save.setOnClickListener(view -> {
            String value = title.getText().toString().trim();
            if (value.isEmpty()) { title.setError("请输入任务"); return; }
            patchTask(item, json("title", value, "rawText", value,
                    "detail", detail.getText().toString().trim(), "deadline", deadline[0]));
            dialog.dismiss();
        });
        dialog.show();
        styleBottom(dialog);
    }

    private String editDeadlineLabel(long time) {
        return "本次截止：" + (time == 0 ? "未设置" : new SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA).format(new Date(time)));
    }

    private void patchTask(TaskItem item, JSONObject patch) {
        new Thread(() -> {
            try {
                TaskItem updated = relay.patch(item, patch);
                TaskCache.upsert(this, updated);
                runOnUiThread(this::refreshList);
            } catch (Exception error) { runOnUiThread(() -> toast("更新失败：" + error.getMessage())); }
        }).start();
    }

    private void deleteTask(TaskItem item) {
        new AlertDialog.Builder(this).setMessage("确定删除这条任务？")
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) -> new Thread(() -> {
                    try { relay.delete(item, Profile.userId(this)); syncNow(false); }
                    catch (Exception error) { runOnUiThread(() -> toast("删除失败：" + error.getMessage())); }
                }).start()).show();
    }

    private AlertDialog bottomDialog(View content) {
        return new AlertDialog.Builder(this).setView(content).create();
    }

    private void styleBottom(AlertDialog dialog) {
        Window window = dialog.getWindow();
        if (window == null) return;
        window.setBackgroundDrawableResource(R.drawable.sheet_background);
        window.setGravity(Gravity.BOTTOM);
        window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private ImageButton iconButton(int icon, int background) {
        ImageButton button = new ImageButton(this);
        button.setImageResource(icon);
        button.setBackgroundResource(background);
        button.setPadding(dp(13), dp(13), dp(13), dp(13));
        return button;
    }

    private ImageButton dockButton(int icon) {
        ImageButton button = new ImageButton(this);
        button.setImageResource(icon);
        button.setBackgroundColor(Color.TRANSPARENT);
        button.setPadding(dp(17), dp(17), dp(17), dp(17));
        return button;
    }

    private View actionButton(String text, Runnable action) {
        TextView button = label(text, 14, PRIMARY, true);
        button.setGravity(Gravity.CENTER);
        button.setPadding(dp(16), dp(10), dp(16), dp(10));
        button.setBackground(round(0xFFF3F6FF, 10));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.rightMargin = dp(10);
        button.setLayoutParams(params);
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private TextView label(String text, float size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private TextView section(String text) {
        TextView view = label(text, 15, SECONDARY, true);
        view.setPadding(0, 0, 0, dp(7));
        return view;
    }

    private EditText input(String hint) {
        EditText input = new EditText(this);
        input.setHint(hint);
        input.setTextSize(16);
        input.setSingleLine(false);
        input.setPadding(dp(14), dp(8), dp(14), dp(8));
        input.setBackground(round(Color.WHITE, 8));
        return input;
    }

    private GradientDrawable round(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private View space(int height) { View view = new View(this); view.setLayoutParams(match(height)); return view; }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private LinearLayout.LayoutParams match(int height) { return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height); }
    private LinearLayout.LayoutParams matchWrap() { return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT); }
    private FrameLayout.LayoutParams frameMatch() { return new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); }
    private LinearLayout.LayoutParams weighted() { return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1); }

    private FrameLayout.LayoutParams dockParams() {
        int width = Math.round(getResources().getDisplayMetrics().widthPixels * 0.86f);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(width, dp(68), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        params.bottomMargin = dp(22);
        return params;
    }

    private FrameLayout.LayoutParams fabParams() {
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(dp(66), dp(66), Gravity.END | Gravity.BOTTOM);
        params.rightMargin = dp(30); params.bottomMargin = dp(106);
        return params;
    }

    private void toast(String text) { Toast.makeText(this, text, Toast.LENGTH_SHORT).show(); }

    private JSONObject json(Object... values) {
        JSONObject result = new JSONObject();
        try {
            for (int index = 0; index + 1 < values.length; index += 2) {
                result.put(String.valueOf(values[index]), values[index + 1]);
            }
        } catch (Exception ignored) {}
        return result;
    }

    private static final class PendingImage {
        final byte[] bytes;
        final Bitmap preview;
        final int width;
        final int height;
        PendingImage(byte[] bytes, Bitmap preview, int width, int height) {
            this.bytes = bytes; this.preview = preview; this.width = width; this.height = height;
        }
    }
}
