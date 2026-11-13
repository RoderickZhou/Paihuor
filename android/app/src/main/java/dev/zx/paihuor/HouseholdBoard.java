package dev.zx.paihuor;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
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
import java.util.function.LongConsumer;
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
    interface DeadlinePicker { void pick(long initial, LongConsumer selected); }
    private final DeadlinePicker deadlinePicker;
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
    private long mutation;
    private String detailCardId;
    private Consumer<HouseholdCard> refreshDetail;

    HouseholdBoard(Activity activity, RelayClient relay, Runnable refreshInbox, DeadlinePicker deadlinePicker, Runnable pickImage) {
        this.activity = activity;
        this.relay = relay;
        this.refreshInbox = refreshInbox;
        this.pickImage = pickImage;
        this.deadlinePicker = deadlinePicker;
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
        long generation = mutation;
        run(() -> {
            JSONArray data = relay.household(current);
            List<HouseholdCard> loaded = new ArrayList<>();
            for (int i = 0; i < data.length(); i++) loaded.add(new HouseholdCard(data.getJSONObject(i)));
            ui(() -> {
                fetching = false;
                if (!family.equals(current) || !current.equals(Profile.familyId(activity))) return;
                if (generation != mutation) { refresh(); return; }
                boolean changed = !this.loaded || loadError != null || !sameCards(loaded, cards);
                cards = loaded;
                this.loaded = true;
                loadError = null;
                if (changed) {
                    render(null);
                    refreshInbox.run();
                    if (refreshDetail != null) {
                        HouseholdCard currentCard = null;
                        for (HouseholdCard card : cards) {
                            if (card.task.objectId.equals(detailCardId)) { currentCard = card; break; }
                        }
                        refreshDetail.accept(currentCard);
                    }
                }
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
            if (!meta(card).isEmpty()) row.addView(text(meta(card), 13, MUTED, false));
            row.setOnClickListener(v -> detail(card));
            actions(row, card, null);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2); params.bottomMargin = dp(8);
            rows.addView(row, params);
        }
    }

    private String meta(HouseholdCard card) {
        List<String> parts = new ArrayList<>();
        if (!card.assignee.isEmpty()) parts.add("wife".equals(card.assignee) ? "老婆" : "老公");
        if (card.task.doneAt > 0) parts.add("完成 " + formatTime(card.task.doneAt));
        if (card.task.deadline > 0) parts.add("截止 " + formatTime(card.task.deadline));
        if (!card.checklist.isEmpty()) parts.add(card.progress());
        if (!card.task.images.isEmpty()) parts.add(card.task.images.size() + " 张照片");
        return String.join(" · ", parts);
    }

    private String formatTime(long value) { return new SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA).format(new Date(value)); }

    void detail(HouseholdCard card) {
        LinearLayout body = column(Color.WHITE);
        body.setPadding(dp(18), dp(8), dp(18), dp(12));
        TextView summary = text(card.list + (meta(card).isEmpty() ? "" : " · " + meta(card)), 14, MUTED, false);
        body.addView(summary);
        if (!card.task.detail.isEmpty()) body.addView(text(card.task.detail, 16, TEXT, false));
        HouseholdCard[] latest = { card };
        TextView progress = text(card.progress(), 14, TEXT, true);
        List<CheckBox> checks = new ArrayList<>();
        if (!card.checklist.isEmpty()) {
            body.addView(progress, full(38));
            for (HouseholdCard.Step step : card.checklist) {
                CheckBox box = new CheckBox(activity);
                box.setText(step.title); box.setTextColor(TEXT); box.setMinHeight(dp(44)); box.setChecked(step.checked);
                box.setEnabled(!card.state.equals("done"));
                box.setOnClickListener(v -> {
                    if (writing) { box.setChecked(!box.isChecked()); return; }
                    boolean selected = box.isChecked();
                    HouseholdCard current = latest[0];
                    String user = Profile.userId(activity);
                    writing = true;
                    for (CheckBox check : checks) check.setEnabled(false);
                    run(() -> {
                        JSONObject payload = new JSONObject().put("itemId", step.id).put("checked", selected);
                        HouseholdCard saved = new HouseholdCard(relay.householdAction(current.task.familyId, user, current, "check", payload));
                        ui(() -> {
                            writing = false;
                            applyCard(saved); refresh();
                        });
                    }, error -> {
                        writing = false; box.setChecked(!selected);
                        for (CheckBox check : checks) check.setEnabled(true);
                        toast("勾选未保存，正在刷新"); refresh();
                    });
                });
                checks.add(box); body.addView(box);
            }
        }
        for (TaskItem.TaskImage photo : card.task.images) {
            ImageView image = new ImageView(activity); image.setContentDescription("卡片照片"); image.setAdjustViewBounds(true);
            body.addView(image, full(180));
            run(() -> { byte[] data = relay.download(photo.id); ui(() -> image.setImageBitmap(android.graphics.BitmapFactory.decodeByteArray(data, 0, data.length))); }, error -> {});
        }
        ScrollView scroll = new ScrollView(activity); scroll.addView(body);
        AlertDialog dialog = new AlertDialog.Builder(activity).setTitle(card.task.title).setView(scroll).setNegativeButton("关闭", null).create();
        actions(body, card, dialog, () -> latest[0]);
        String user = Profile.userId(activity);
        boolean creator = user.equals(card.task.fromUserId);
        if (creator || user.equals(card.assignee)) {
            LinearLayout tools = new LinearLayout(activity);
            Button edit = button("编辑／移动");
            edit.setTextColor(BLUE);
            edit.setOnClickListener(v -> editCard(latest[0], dialog));
            tools.addView(edit, new LinearLayout.LayoutParams(0, dp(44), 1));
            if (creator) {
                Button remove = button("删除");
                remove.setTextColor(0xFFB43D45);
                remove.setOnClickListener(v -> new AlertDialog.Builder(activity).setTitle("删除卡片？")
                        .setMessage("这张卡会从两台手机上移除。").setNegativeButton("取消", null)
                        .setPositiveButton("删除", (confirm, which) -> change(latest[0], "delete", dialog)).show());
                tools.addView(remove, new LinearLayout.LayoutParams(0, dp(44), 1));
            }
            body.addView(tools);
        }
        detailCardId = card.task.objectId;
        Consumer<HouseholdCard> binding = updated -> {
            HouseholdCard current = latest[0];
            if (updated == null) { dialog.dismiss(); return; }
            if (updated.revision < current.revision) return;
            if (!sameDetail(current, updated)) {
                if (editor != null || writing) {
                    dialog.dismiss();
                    return;
                }
                dialog.dismiss();
                detail(updated);
                return;
            }
            latest[0] = updated;
            summary.setText(updated.list + (meta(updated).isEmpty() ? "" : " · " + meta(updated)));
            progress.setText(updated.progress());
            for (int i = 0; i < checks.size(); i++) {
                checks.get(i).setChecked(updated.checklist.get(i).checked);
                checks.get(i).setEnabled(!writing && !updated.state.equals("done"));
            }
        };
        refreshDetail = binding;
        dialog.setOnDismissListener(d -> {
            if (refreshDetail == binding) { refreshDetail = null; detailCardId = null; }
        });
        dialog.show();
    }

    private boolean sameDetail(HouseholdCard current, HouseholdCard updated) {
        if (!current.state.equals(updated.state) || !current.assignee.equals(updated.assignee)
                || !current.task.title.equals(updated.task.title) || !current.task.detail.equals(updated.task.detail)
                || current.checklist.size() != updated.checklist.size()) return false;
        for (int i = 0; i < current.checklist.size(); i++) {
            HouseholdCard.Step a = current.checklist.get(i), b = updated.checklist.get(i);
            if (!a.id.equals(b.id) || !a.title.equals(b.title)) return false;
        }
        return true;
    }

    private void applyCard(HouseholdCard updated) {
        if (!updated.task.familyId.equals(family)) return;
        mutation++;
        for (int i = 0; i < cards.size(); i++) {
            HouseholdCard current = cards.get(i);
            if (current.task.objectId.equals(updated.task.objectId)) {
                if (current.revision <= updated.revision) cards.set(i, updated);
                if (refreshDetail != null && updated.task.objectId.equals(detailCardId)) refreshDetail.accept(cards.get(i));
                break;
            }
        }
        render(null);
        refreshInbox.run();
    }

    private void editCard(HouseholdCard card, AlertDialog detail) {
        LinearLayout form = column(Color.WHITE);
        form.setPadding(dp(18), dp(8), dp(18), dp(12));
        EditText title = input("卡片标题", card.task.title, 1);
        EditText note = input("备注", card.task.detail, 3);
        EditText list = input("清单名", card.list, 1);
        form.addView(text("卡片标题", 14, MUTED, false)); form.addView(title);
        form.addView(text("备注", 14, MUTED, false)); form.addView(note);
        form.addView(text("移动到清单", 14, MUTED, false)); form.addView(list);
        Button choose = button("选择已有清单");
        choose.setOnClickListener(v -> {
            LinkedHashSet<String> names = new LinkedHashSet<>(); names.add("日常");
            for (HouseholdCard item : cards) names.add(item.list);
            String[] choices = names.toArray(new String[0]);
            new AlertDialog.Builder(activity).setTitle("移动到清单").setItems(choices, (d, i) -> list.setText(choices[i])).show();
        });
        form.addView(choose);
        CardExtras extras = new CardExtras(form, card.task.deadline, card.checklist);
        ScrollView scroll = new ScrollView(activity); scroll.addView(form);
        AlertDialog editor = new AlertDialog.Builder(activity).setTitle("编辑卡片").setView(scroll)
                .setNegativeButton("取消", null).setPositiveButton("保存", null).show();
        editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            if (writing) return;
            String name = title.getText().toString().trim(), notes = note.getText().toString().trim(), group = list.getText().toString().trim();
            if (name.isEmpty() || name.length() > 120 || notes.length() > 2000 || group.length() > 40) {
                toast("请检查标题、备注和清单名"); return;
            }
            String current = Profile.familyId(activity), user = Profile.userId(activity);
            if (!current.equals(card.task.familyId)) return;
            JSONArray steps = extras.steps();
            if (steps == null) return;
            long deadline = extras.deadline;
            writing = true;
            run(() -> {
                relay.householdAction(current, user, card, "edit", new JSONObject().put("title", name).put("detail", notes)
                        .put("list", group).put("deadline", deadline).put("checklist", steps));
                ui(() -> { writing = false; editor.dismiss(); detail.dismiss(); selectedList = group.isEmpty() ? "日常" : group; render(null); refresh(); });
            }, error -> { writing = false; toast("保存失败，修改未丢失"); refresh(); });
        });
    }

    private void actions(LinearLayout parent, HouseholdCard card, AlertDialog detail) {
        actions(parent, card, detail, () -> card);
    }

    private void actions(LinearLayout parent, HouseholdCard card, AlertDialog detail, java.util.function.Supplier<HouseholdCard> latest) {
        LinearLayout bar = new LinearLayout(activity);
        if (card.state.equals("available")) action(bar, "认领", latest, "claim", detail);
        else if (card.state.equals("claimed") && card.assignee.equals(Profile.userId(activity))) {
            action(bar, "放回", latest, "release", detail);
            action(bar, "完成", latest, "complete", detail);
        } else if (card.state.equals("done") && card.assignee.equals(Profile.userId(activity))) action(bar, "撤销完成", latest, "reopen", detail);
        if (bar.getChildCount() > 0) parent.addView(bar);
    }

    private void action(LinearLayout bar, String label, java.util.function.Supplier<HouseholdCard> card, String action, AlertDialog detail) {
        Button button = button(label);
        button.setTextColor(BLUE);
        button.setOnClickListener(v -> change(card.get(), action, detail));
        bar.addView(button, new LinearLayout.LayoutParams(0, dp(44), 1));
    }

    void change(HouseholdCard card, String action, AlertDialog detail) {
        if (writing) return;
        String current = Profile.familyId(activity), role = Profile.userId(activity);
        if (!current.equals(card.task.familyId)) return;
        writing = true;
        run(() -> {
            relay.householdAction(current, role, card, action);
            ui(() -> { writing = false; if (detail != null) detail.dismiss(); if (action.equals("reopen")) { tab = 1; render(null); } refresh(); });
        }, error -> { writing = false; if (detail != null) detail.dismiss(); toast("卡片状态可能已变化，正在刷新"); refresh(); });
    }

    private static final class Editor {
        final String[] ids = new String[50];
        final List<String> images = new ArrayList<>();
        Button photo;
        Button clear;
        String signature = "";
    }

    private final class CardExtras {
        long deadline;
        final List<EditText> fields = new ArrayList<>();
        final List<String> ids = new ArrayList<>();
        final LinearLayout rows;
        final Button add;

        CardExtras(LinearLayout form, long time, List<HouseholdCard.Step> existing) {
            deadline = time;
            LinearLayout due = new LinearLayout(activity);
            Button pick = button(deadlineLabel());
            Button clear = button("清除");
            clear.setVisibility(deadline > 0 ? View.VISIBLE : View.GONE);
            pick.setOnClickListener(v -> deadlinePicker.pick(deadline, value -> {
                deadline = value; pick.setText(deadlineLabel()); clear.setVisibility(View.VISIBLE);
            }));
            clear.setOnClickListener(v -> { deadline = 0; pick.setText(deadlineLabel()); clear.setVisibility(View.GONE); });
            due.addView(pick, new LinearLayout.LayoutParams(0, dp(44), 1));
            due.addView(clear, new LinearLayout.LayoutParams(dp(60), dp(44))); form.addView(due);
            rows = column(Color.WHITE); form.addView(rows);
            add = button("添加子项"); add.setTextColor(BLUE);
            add.setOnClickListener(v -> append(UUID.randomUUID().toString(), ""));
            form.addView(add, full(44));
            for (HouseholdCard.Step step : existing) append(step.id, step.title);
        }

        private String deadlineLabel() { return "截止时间：" + (deadline == 0 ? "未设置" : formatTime(deadline)); }

        private void append(String id, String title) {
            if (fields.size() >= 30) return;
            LinearLayout row = new LinearLayout(activity);
            EditText field = input("子项", title, 1);
            Button remove = icon(R.drawable.icon_house_close, "移除子项");
            row.addView(field, new LinearLayout.LayoutParams(0, dp(48), 1));
            row.addView(remove, new LinearLayout.LayoutParams(dp(44), dp(44)));
            fields.add(field); ids.add(id); rows.addView(row);
            add.setEnabled(fields.size() < 30);
            remove.setOnClickListener(v -> { int index = fields.indexOf(field); fields.remove(index); ids.remove(index); rows.removeView(row); add.setEnabled(true); });
            if (title.isEmpty()) field.requestFocus();
        }

        JSONArray steps() {
            JSONArray result = new JSONArray();
            for (int i = 0; i < fields.size(); i++) {
                String value = fields.get(i).getText().toString().trim();
                if (value.isEmpty() || value.length() > 120) { fields.get(i).setError("请输入 1 到 120 字"); return null; }
                try { result.put(new JSONObject().put("id", ids.get(i)).put("title", value)); }
                catch (org.json.JSONException error) { throw new IllegalStateException(error); }
            }
            return result;
        }
    }

    private void edit() {
        Editor draft = new Editor(); editor = draft;
        LinearLayout form = column(Color.WHITE);
        form.setPadding(dp(18), dp(6), dp(18), dp(8));
        EditText list = input("清单名", selectedList.isEmpty() ? "日常" : selectedList, 1);
        EditText titles = input("卡片标题（每行一张）", "", 4);
        EditText note = input("备注（单张卡片）", "", 2);
        form.addView(list); form.addView(titles); form.addView(note);
        CardExtras extras = new CardExtras(form, 0, java.util.Collections.emptyList());
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
            JSONArray steps = extras.steps();
            if (steps == null) return;
            long deadline = extras.deadline;
            if (values.size() > 1 && (!detail.isEmpty() || !draft.images.isEmpty() || deadline != 0 || steps.length() > 0)) {
                toast("备注、照片、截止时间和子清单仅用于单张卡片"); return;
            }
            String signature = new JSONArray().put(name).put(new JSONArray(values)).put(detail).put(new JSONArray(draft.images)).put(deadline).put(steps).toString();
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
                        .put("detail", detail).put("imageIds", new JSONArray(imageIds)).put("deadline", deadline).put("checklist", steps));
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
