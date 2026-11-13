package dev.zx.paihuor;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public final class TaskAdapter extends BaseAdapter {
    public interface Listener {
        void onOpen(TaskItem item);
        void onCheck(TaskItem item);
        void onMore(TaskItem item, View anchor);
    }

    private final Context context;
    private final Listener listener;
    private final String userId;
    private List<TaskItem> items = new ArrayList<>();

    public TaskAdapter(Context context, String userId, Listener listener) {
        this.context = context;
        this.userId = userId;
        this.listener = listener;
    }

    public void setItems(List<TaskItem> items) {
        this.items = items;
        notifyDataSetChanged();
    }

    @Override public int getCount() { return items.size(); }
    @Override public TaskItem getItem(int position) { return items.get(position); }
    @Override public long getItemId(int position) { return position; }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        TaskItem item = getItem(position);
        LinearLayout card = new LinearLayout(context);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.TOP);
        card.setPadding(dp(16), dp(15), dp(12), dp(15));
        card.setBackground(round(Color.WHITE, 8));
        card.setElevation(dp(2));

        TextView check = new TextView(context);
        check.setGravity(Gravity.CENTER);
        check.setText("done".equals(item.status) || item.archived ? "✓" : "");
        check.setTextColor(Color.WHITE);
        check.setTextSize(13);
        check.setTypeface(Typeface.DEFAULT_BOLD);
        check.setBackground(checkBackground("done".equals(item.status) || item.archived));
        check.setOnClickListener(view -> listener.onCheck(item));
        LinearLayout.LayoutParams checkParams = new LinearLayout.LayoutParams(dp(22), dp(22));
        checkParams.topMargin = dp(2);
        card.addView(check, checkParams);

        LinearLayout copy = new LinearLayout(context);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(dp(12), 0, 0, 0);
        TextView title = text(item.title.isEmpty() ? item.rawText : item.title, 16, 0xFF17181C);
        title.setTypeface(Typeface.DEFAULT, Typeface.NORMAL);
        title.setMaxLines(2);
        if ("done".equals(item.status) || item.archived) title.setAlpha(0.55f);
        copy.addView(title);

        String meta = directionText(item);
        if (item.deadline > 0) {
            meta = new SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA).format(new Date(item.deadline)) + "  ·  " + meta;
        }
        if (!item.images.isEmpty()) meta += "  ·  图片 " + item.images.size() + " 张";
        TextView status = text(meta, 11, 0xFF9AA2B3);
        status.setPadding(0, dp(6), 0, 0);
        copy.addView(status);
        if (!item.detail.isEmpty()) {
            TextView detail = text(item.detail, 13, 0xFF9AA2B3);
            detail.setMaxLines(2);
            detail.setPadding(0, dp(5), 0, 0);
            copy.addView(detail);
        }
        card.addView(copy, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        card.setOnClickListener(view -> listener.onOpen(item));
        card.setOnLongClickListener(view -> {
            listener.onMore(item, view);
            return true;
        });

        LinearLayout outer = new LinearLayout(context);
        outer.setPadding(dp(18), dp(5), dp(18), dp(7));
        outer.addView(card, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        return outer;
    }

    private String directionText(TaskItem item) {
        String direction = item.fromUserId.equals(userId) ? "我派给对方" : "对方派给我";
        if (item.fromUserId.equals(userId) && !"done".equals(item.status) && !"negotiating".equals(item.status)) {
            return direction + " · " + TaskRepository.receipt(item);
        }
        String status;
        switch (item.status) {
            case "received": status = "已收到"; break;
            case "negotiating": status = "商量中"; break;
            case "done": status = "已完成"; break;
            default: status = "待收到"; break;
        }
        return direction + " · " + status;
    }

    private TextView text(String value, float size, int color) {
        TextView view = new TextView(context);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        return view;
    }

    private GradientDrawable checkBackground(boolean checked) {
        GradientDrawable drawable = round(checked ? 0xFF477CFF : Color.TRANSPARENT, 5);
        drawable.setStroke(dp(2), checked ? 0xFF477CFF : 0xFF9AA2B3);
        return drawable;
    }

    private GradientDrawable round(int color, int radius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radius));
        return drawable;
    }

    private int dp(int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
