package dev.zx.paihuor;

import android.annotation.SuppressLint;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.json.JSONException;
import org.json.JSONObject;
import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.android.RecognitionListener;
import org.vosk.android.SpeechService;

final class MandarinSpeech {
    private static final String MODEL = "vosk-model-small-cn-0.22";
    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private Model model;
    private SpeechService speech;
    private Recognizer recognizer;
    private int generation;

    MandarinSpeech(Context context) { this.context = context.getApplicationContext(); }

    void prepare(Consumer<Boolean> ready) {
        worker.execute(() -> {
            try {
                if (model == null) model = new Model(modelPath());
                main.post(() -> ready.accept(true));
            } catch (Exception | LinkageError error) {
                main.post(() -> ready.accept(false));
            }
        });
    }

    @SuppressLint("MissingPermission")
    void start(Consumer<String> partial, Consumer<String> complete, Runnable failed) {
        int session = ++generation;
        worker.execute(() -> {
            try {
                recognizer = new Recognizer(model, 16000f);
                speech = new SpeechService(recognizer, 16000f);
                speech.startListening(new RecognitionListener() {
                    private final StringBuilder committed = new StringBuilder();

                    @Override public void onPartialResult(String value) {
                        if (session == generation) partial.accept(normalize(committed + " " + field(value, "partial")));
                    }
                    @Override public void onResult(String value) {
                        committed.append(' ').append(field(value, "text"));
                        if (session == generation) partial.accept(normalize(committed.toString()));
                    }
                    @Override public void onFinalResult(String value) {
                        if (session == generation) complete.accept(normalize(committed + " " + field(value, "text")));
                    }
                    @Override public void onError(Exception error) { fail(); }
                    @Override public void onTimeout() { fail(); }

                    private void fail() {
                        if (session != generation) return;
                        failed.run();
                    }
                }, 45000);
            } catch (Exception | LinkageError error) {
                release(true);
                main.post(() -> { if (session == generation) failed.run(); });
            }
        });
    }

    void finish() { worker.execute(() -> release(false)); }

    void cancel() {
        generation++;
        worker.execute(() -> release(true));
    }

    void close() {
        cancel();
        worker.execute(() -> { if (model != null) model.close(); });
        worker.shutdown();
    }

    private void release(boolean discard) {
        if (speech != null) {
            if (discard) speech.cancel(); else speech.stop();
            speech.shutdown();
            speech = null;
        }
        if (recognizer != null) {
            recognizer.close();
            recognizer = null;
        }
    }

    private String modelPath() throws IOException {
        File root = context.getNoBackupFilesDir();
        File dir = new File(root, MODEL);
        File ready = new File(dir, ".ready");
        if (ready.isFile()) return dir.getPath();
        String prefix = dir.getCanonicalPath() + File.separator;
        try (ZipInputStream zip = new ZipInputStream(context.getAssets().open(MODEL + ".zip"))) {
            byte[] buffer = new byte[32768];
            for (ZipEntry entry; (entry = zip.getNextEntry()) != null; ) {
                if (entry.isDirectory()) continue;
                File file = new File(root, entry.getName());
                if (!file.getCanonicalPath().startsWith(prefix)) throw new IOException("Invalid speech model path");
                File parent = file.getParentFile();
                if (!parent.isDirectory() && !parent.mkdirs()) throw new IOException("Cannot unpack speech model");
                try (FileOutputStream output = new FileOutputStream(file)) {
                    for (int n; (n = zip.read(buffer)) != -1; ) output.write(buffer, 0, n);
                }
            }
        }
        if (!new File(dir, "am/final.mdl").isFile() || !ready.createNewFile()) throw new IOException("Incomplete speech model");
        return dir.getPath();
    }

    private static String field(String json, String name) {
        try { return new JSONObject(json).optString(name); }
        catch (JSONException ignored) { return ""; }
    }

    private static String normalize(String text) {
        return text.trim().replaceAll("(?<=[\\u3400-\\u9fff])\\s+(?=[\\u3400-\\u9fff])", "");
    }
}
