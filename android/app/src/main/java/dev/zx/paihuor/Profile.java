package dev.zx.paihuor;

import android.content.Context;
import android.content.SharedPreferences;

public final class Profile {
    private static final String NAME = "paihuor_profile";

    private Profile() {}

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(NAME, Context.MODE_PRIVATE);
    }

    public static boolean isComplete(Context context) {
        return !familyId(context).isEmpty() && !userId(context).isEmpty();
    }

    public static String familyId(Context context) {
        return preferences(context).getString("familyId", "").trim();
    }

    public static String userId(Context context) {
        return preferences(context).getString("userId", "").trim();
    }

    public static String userName(Context context) {
        String fallback = "wife".equals(userId(context)) ? "老婆" : "老公";
        return preferences(context).getString("userName", fallback).trim();
    }

    public static String counterpart(Context context) {
        return "wife".equals(userId(context)) ? "husband" : "wife";
    }

    public static synchronized String deviceId(Context context) {
        String current = preferences(context).getString("deviceId", "");
        if (!current.isEmpty()) return current;
        String id = java.util.UUID.randomUUID().toString();
        preferences(context).edit().putString("deviceId", id).apply();
        return id;
    }

    public static void save(Context context, String familyId, String userId, String userName) {
        preferences(context).edit()
                .putString("familyId", familyId.trim())
                .putString("userId", "wife".equals(userId) ? "wife" : "husband")
                .putString("userName", userName.trim())
                .apply();
    }
}
