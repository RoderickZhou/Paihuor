package dev.zx.paihuor;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.function.Consumer;
import org.json.JSONArray;
import org.json.JSONObject;

final class HouseholdBoard {
    private static final int BLUE = 0xFF2F63E6, TEXT = 0xFF17181C, MUTED = 0xFF596274, BG = 0xFFF3F6FF;
    private static final String[] STATES = {"available", "claimed", "done"};
    private static final String[] LABELS = {"待认领", "进行中", "已完成"};
    private final Activity activity;
    private final RelayClient relay;
    private final Runnable refreshInbox;
    private final Runnable pickImage;
    private List<HouseholdCard> cards = new ArrayList<>();
    private String family = "";
    private String selectedList = "";
    private int tab;
    private boolean fetching, writing;
    private boolean loaded;
    private String loadError;
    private AlertDialog board;
    private LinearLayout rows;
    private Button lists;
    private Button[] tabs;
    private Editor editor;

    HouseholdBoard(Activity activity, RelayClient relay, Runnable refreshInbox, Runnable pickImage) {
        this.activity = activity;
        this.relay = relay;
        this.refreshInbox = refreshInbox;
        this.pickImage = pickImage;
    }

    List<TaskItem> claimed(String family, String user) {
        List<TaskItem> result = new ArrayList<>();
        if (this.family.equals(family)) for (HouseholdCard card : cards) {
            if (card.state.equals("claimed") && card.assignee.equals(user)) result.add(card.task);
        }
        return result;
    }

    void refresh() {
        String current = Profile.familyId(activity);
        if (!current.equals(family)) {
            family = current;
            cards = new ArrayList<>();
            selectedList = "";
            loaded = false;
            loadError = null;
        }
        if (fetching || current.isEmpty()) return;
        fetching = true;
        run(() -> {
            JSONArray data = relay.household(current);
            List<HouseholdCard> loaded = new ArrayList<>();
            for (int i = 0; i < data.length(); i++) loaded.add(new HouseholdCard(data.getJSONObject(i)));
            ui(() -> {
                fetching = false;
                if (!family.equals(current) || !current.equals(Profile.familyId(activity))) return;
                boolean changed = !this.loaded || loadError != null || !sameCards(loaded, cards);
                cards = loaded;
                this.loaded = true;
                loadError = null;
                if (changed) { render(null); refreshInbox.run(); }
            });
        }, error -> {
            fetching = false;
            if (current.equals(family) && loadError == null) {
                loadError = "暂时无法同步";
                render(loadError);
            }
        });
    }

    private boolean sameCards(List<HouseholdCard> left, List<HouseholdCard> right) {
        if (left.size() != right.size()) return false;
        for (int i = 0; i < left.size(); i++) {
            HouseholdCard a = left.get(i), b = right.get(i);
            if (!a.task.objectId.equals(b.task.objectId) || a.revision != b.revision) return false;
        }
        return true;
    }

    void show() {
        tab = 0;
        selectedList = "";
        LinearLayout page = column(BG);
        page.setPadding(dp(18), dp(12), dp(18), dp(12));
        LinearLayout header = new LinearLayout(activity);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(text("家里待办", 25, TEXT, true), new LinearLayout.LayoutParams(0, dp(54), 1));
        Button add = icon(R.drawable.icon_house_add, "加卡");
        add.setOnClickListener(v -> edit());
        header.addView(add, new LinearLayout.LayoutParams(dp(48), dp(48)));
        Button close = icon(R.drawable.icon_house_close, "关闭");
        close.setOnClickListener(v -> board.dismiss());
        header.addView(close, new LinearLayout.LayoutParams(dp(48), dp(48)));
        page.addView(header);
        lists = button("全部清单");
        lists.setOnClickListener(v -> pickList());
        page.addView(lists, full(44));
        LinearLayout bar = new LinearLayout(activity);
        tabs = new Button[3];
        for (int i = 0; i < 3; i++) {
            final int selected = i;
            tabs[i] = button(LABELS[i]);
            tabs[i].setOnClickListener(v -> { tab = selected; render(null); });
            bar.addView(tabs[i], new LinearLayout.LayoutParams(0, dp(46), 1));
        }
        page.addView(bar);
        ScrollView scroll = new ScrollView(activity);
        rows = column(BG);
        scroll.addView(rows);
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        board = new AlertDialog.Builder(activity).setView(page).create();
        board.show();
        board.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        board.getWindow().setLayout(-1, -1);
        render(null);
        refresh();
    }

    private void pickList() {
        LinkedHashSet<String> names = new LinkedHashSet<>();
        names.add("");
        names.add("日常");
        for (HouseholdCard card : cards) names.add(card.list);
        String[] values = names.toArray(new String[0]), labels = values.clone();
        labels[0] = "全部清单";
        new AlertDialog.Builder(activity).setTitle("清单").setItems(labels, (d, index) -> {
            selectedList = values[index]; render(null);
        }).show();
    }

    private void render(String error) {
        if (board == null || !board.isShowing()) return;
        if (error == null) error = loadError;
        int[] counts = new int[3];
        List<HouseholdCard> visible = new ArrayList<>();
        for (HouseholdCard card : cards) {
            if (!selectedList.isEmpty() && !selectedList.equals(card.list)) continue;
            for (int i = 0; i < 3; i++) if (STATES[i].equals(card.state)) counts[i]++;
            if (STATES[tab].equals(card.state)) visible.add(card);
        }
        if (tab == 2) visible.sort((a, b) -> Long.compare(b.task.doneAt, a.task.doneAt));
        lists.setText((selectedList.isEmpty() ? "全部清单" : selectedList) + "  ▾");
        for (int i = 0; i < 3; i++) {
            tabs[i].setText(LABELS[i] + " " + counts[i]);
            tabs[i].setSelected(i == tab);
            tabs[i].setTextColor(i == tab ? BLUE : TEXT);
            tabs[i].setBackground(round(i == tab ? 0xFFDDE6FF : Color.TRANSPARENT));
        }
        rows.removeAllViews();
        if (error != null) {
            Button retry = button(error + " · 重试"); retry.setOnClickListener(v -> refresh()); rows.addView(retry, full(48));
        }
        if (visible.isEmpty() && error == null) rows.addView(text(loaded ? "暂无" + LABELS[tab] + "卡片" : "正在同步…", 15, MUTED, false), full(70));
        String previous = null;
        if (tab != 2) visible.sort((a, b) -> a.list.compareTo(b.list));
        for (HouseholdCard card : visible) {
            if (!card.list.equals(previous) && selectedList.isEmpty() && tab != 2) {
                rows.addView(text(card.list, 14, MUTED, true), full(42)); previous = card.list;
            }
            LinearLayout row = column(Color.WHITE);
            row.setBackground(round(Color.WHITE));
            row.setPadding(dp(12), dp(8), dp(12), dp(8));
            TextView title = text(card.task.title, 16, TEXT, true);
            row.addView(title);
            if (!card.task.detail.isEmpty()) {
                TextView note = text(card.task.detail, 14, MUTED, false); note.setMaxLines(2); row.addView(note);
            }
            if (!card.assignee.isEmpty() || !card.task.images.isEmpty()) row.addView(text(meta(card), 13, MUTED, false));
            row.setOnClickListener(v -> detail(card));
            actions(row, card, null);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2); params.bottomMargin = dp(8);
            rows.addView(row, params);
        }
    }

    private String meta(HouseholdCard card) {
        String name = card.assignee.isEmpty() ? "" : "wife".equals(card.assignee) ? "老婆" : "老公";
        if (card.task.doneAt > 0) name += " · " + new SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA).format(new Date(card.task.doneAt));
        return name + (card.task.images.isEmpty() ? "" : (name.isEmpty() ? "" : " · ") + card.task.images.size() + " 张照片");
    }

    void detail(HouseholdCard card) {
        LinearLayout body = column(Color.WHITE);
        body.setPadding(dp(18), dp(8), dp(18), dp(12));
        body.addView(text(card.list + (meta(card).isEmpty() ? "" : " · " + meta(card)), 14, MUTED, false));
        if (!card.task.detail.isEmpty()) body.addView(text(card.task.detail, 16, TEXT, false));
        for (TaskItem.TaskImage photo : card.task.images) {
            ImageView image = new ImageView(activity); image.setContentDescription("卡片照片"); image.setAdjustViewBounds(true);
            body.addView(image, full(180));
            run(() -> { byte[] data = relay.download(photo.id); ui(() -> image.setImageBitmap(android.graphics.BitmapFactory.decodeByteArray(data, 0, data.length))); }, error -> {});
        }
        ScrollView scroll = new ScrollView(activity); scroll.addView(body);
        AlertDialog dialog = new AlertDialog.Builder(activity).setTitle(card.task.title).setView(scroll).setNegativeButton("关闭", null).create();
        actions(body, card, dialog);
        dialog.show();
    }

    private void actions(LinearLayout parent, HouseholdCard card, AlertDialog detail) {
        LinearLayout bar = new LinearLayout(activity);
        if (card.state.equals("available")) action(bar, "认领", card, "claim", detail);
        else if (card.state.equals("claimed") && card.assignee.equals(Profile.userId(activity))) {
            action(bar, "放回", card, "release", detail);
            action(bar, "完成", card, "complete", detail);
        }
        if (bar.getChildCount() > 0) parent.addView(bar);
    }

    private void action(LinearLayout bar, String label, HouseholdCard card, String action, AlertDialog detail) {
        Button button = button(label);
        button.setTextColor(BLUE);
        button.setOnClickListener(v -> change(card, action, detail));
        bar.addView(button, new LinearLayout.LayoutParams(0, dp(44), 1));
    }

    void change(HouseholdCard card, String action, AlertDialog detail) {
        if (writing) return;
        String current = Profile.familyId(activity), role = Profile.userId(activity);
        if (!current.equals(card.task.familyId)) return;
        writing = true;
        run(() -> {
            relay.householdAction(current, role, card, action);
            ui(() -> { writing = false; if (detail != null) detail.dismiss(); refresh(); });
        }, error -> { writing = false; if (detail != null) detail.dismiss(); toast("卡片状态可能已变化，正在刷新"); refresh(); });
    }

    private static final class Editor {
        final String[] ids = new String[50];
        final List<String> images = new ArrayList<>();
        Button photo;
        Button clear;
        String signature = "";
    }

    private void edit() {
        Editor draft = new Editor(); editor = draft;
        LinearLayout form = column(Color.WHITE);
        form.setPadding(dp(18), dp(6), dp(18), dp(8));
        EditText list = input("清单名", selectedList.isEmpty() ? "日常" : selectedList, 1);
        EditText titles = input("卡片标题（每行一张）", "", 4);
        EditText note = input("备注（单张卡片）", "", 2);
        form.addView(list); form.addView(titles); form.addView(note);
        draft.photo = button("添加照片");
        draft.photo.setOnClickListener(v -> pickImage.run());
        LinearLayout photos = new LinearLayout(activity);
        photos.addView(draft.photo, new LinearLayout.LayoutParams(0, dp(44), 1));
        draft.clear = button("清除照片");
        draft.clear.setVisibility(View.GONE);
        draft.clear.setOnClickListener(v -> {
            if (!draft.photo.isEnabled() || writing) return;
            draft.images.clear(); draft.photo.setText("添加照片"); draft.clear.setVisibility(View.GONE);
        });
        photos.addView(draft.clear, new LinearLayout.LayoutParams(0, dp(44), 1));
        form.addView(photos);
        ScrollView scroll = new ScrollView(activity); scroll.addView(form);
        AlertDialog dialog = new AlertDialog.Builder(activity).setTitle("添加卡片").setView(scroll)
                .setNegativeButton("取消", null).setPositiveButton("添加", null).create();
        dialog.setOnDismissListener(ignored -> { if (editor == draft) editor = null; });
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            if (writing || !draft.photo.isEnabled()) return;
            List<String> values = new ArrayList<>();
            for (String line : titles.getText().toString().split("\\R")) if (!line.trim().isEmpty()) values.add(line.trim());
            String name = list.getText().toString().trim(), detail = note.getText().toString().trim();
            if (name.length() > 40 || detail.length() > 2000 || values.isEmpty() || values.size() > 50
                    || values.stream().anyMatch(line -> line.length() > 120)) { toast("请检查清单名、标题和数量（最多 50 张）"); return; }
            if (values.size() > 1 && (!detail.isEmpty() || !draft.images.isEmpty())) { toast("备注和照片仅用于单张卡片"); return; }
            String signature = new JSONArray().put(name).put(new JSONArray(values)).put(detail).put(new JSONArray(draft.images)).toString();
            if (!signature.equals(draft.signature)) {
                draft.signature = signature;
                for (int i = 0; i < values.size(); i++) draft.ids[i] = UUID.randomUUID().toString();
            }
            String current = Profile.familyId(activity), role = Profile.userId(activity);
            List<String> imageIds = new ArrayList<>(draft.images);
            writing = true;
            run(() -> {
                JSONArray items = new JSONArray();
                for (int i = 0; i < values.size(); i++) items.put(new JSONObject().put("id", draft.ids[i]).put("title", values.get(i))
                        .put("detail", detail).put("imageIds", new JSONArray(imageIds)));
                relay.addHousehold(current, role, name, items);
                ui(() -> { writing = false; tab = 0; selectedList = name.isEmpty() ? "日常" : name; dialog.dismiss(); render(null); refresh(); });
            }, error -> { writing = false; toast("添加失败，原稿已保留，可以重试"); });
        });
    }

    void attach(byte[] bytes, int width, int height) {
        Editor draft = editor;
        if (draft == null || writing || draft.images.size() >= 9) return;
        String current = Profile.familyId(activity);
        draft.photo.setEnabled(false); draft.photo.setText("上传中…");
        run(() -> {
            String id = relay.upload(bytes, current, width, height).id;
            if (id.isEmpty()) throw new IllegalStateException("Missing attachment id");
            ui(() -> {
                if (editor != draft) return;
                draft.images.add(id); draft.photo.setEnabled(true);
                draft.photo.setText("添加照片 · " + draft.images.size() + "/9");
                draft.clear.setVisibility(View.VISIBLE);
            });
        }, error -> { if (editor == draft) { draft.photo.setEnabled(true); draft.photo.setText("添加照片"); toast("照片上传失败"); } });
    }

    private interface Work { void run() throws Exception; }
    private void run(Work work, Consumer<Exception> failure) {
        new Thread(() -> { try { work.run(); } catch (Exception error) { ui(() -> failure.accept(error)); } }, "household-board").start();
    }
    private void ui(Runnable work) { activity.runOnUiThread(() -> { if (!activity.isDestroyed()) work.run(); }); }
    private void toast(String message) { Toast.makeText(activity, message, Toast.LENGTH_SHORT).show(); }
    private int dp(int size) { return Math.round(size * activity.getResources().getDisplayMetrics().density); }
    private LinearLayout.LayoutParams full(int height) { return new LinearLayout.LayoutParams(-1, dp(height)); }
    private LinearLayout column(int color) { LinearLayout view = new LinearLayout(activity); view.setOrientation(LinearLayout.VERTICAL); view.setBackgroundColor(color); return view; }
    private GradientDrawable round(int color) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(8)); return d; }
    private TextView text(String title, int size, int color, boolean bold) { TextView v = new TextView(activity); v.setText(title); v.setTextSize(size); v.setTextColor(color); v.setGravity(Gravity.CENTER_VERTICAL); if (bold) v.setTypeface(Typeface.DEFAULT_BOLD); return v; }
    private Button button(String title) { Button v = new Button(activity); v.setText(title); v.setTextColor(TEXT); v.setTextSize(14); v.setMinHeight(0); v.setAllCaps(false); return v; }
    private Button icon(int asset, String name) { Button v = button(""); v.setContentDescription(name); v.setTooltipText(name); v.setBackgroundColor(Color.TRANSPARENT); v.setCompoundDrawablesWithIntrinsicBounds(0, asset, 0, 0); v.setPadding(0, dp(12), 0, 0); return v; }
    private EditText input(String hint, String initial, int lines) {
        EditText v = new EditText(activity); v.setHint(hint); v.setText(initial); v.setTextColor(TEXT);
        if (lines == 1) v.setSingleLine();
        else { v.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);
            v.setGravity(Gravity.TOP); v.setMinLines(lines); v.setMaxLines(8); }
        return v;
    }
}
