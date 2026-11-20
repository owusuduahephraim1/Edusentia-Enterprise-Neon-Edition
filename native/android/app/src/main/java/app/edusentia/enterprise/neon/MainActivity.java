package app.edusentia.enterprise.neon;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.util.Base64;

import androidx.webkit.JavaScriptReplyProxy;
import androidx.webkit.WebMessageCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Collections;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import android.widget.FrameLayout;
import android.widget.Toast;

import com.google.android.play.core.appupdate.AppUpdateInfo;
import com.google.android.play.core.appupdate.AppUpdateManager;
import com.google.android.play.core.appupdate.AppUpdateManagerFactory;
import com.google.android.play.core.appupdate.AppUpdateOptions;
import com.google.android.play.core.install.model.AppUpdateType;
import com.google.android.play.core.install.model.UpdateAvailability;

import java.util.Locale;

public class MainActivity extends Activity {
    private static final String HOME_URL = "https://owusuduahephraim1.github.io/Edusentia-Enterprise-Neon-Edition/";
    private static final int FILE_CHOOSER_REQUEST = 6040;
    private static final int PLAY_UPDATE_REQUEST = 6050;
    private static final int DOCUMENT_SAVE_REQUEST = 6060;
    private static final long MAX_DOCUMENT_BYTES = 64L * 1024L * 1024L;
    private static final int MAX_BASE64_CHUNK = 48 * 1024;

    private WebView webView;
    private AppUpdateManager appUpdateManager;
    private ValueCallback<Uri[]> filePathCallback;
    private final ExecutorService documentIo = Executors.newSingleThreadExecutor();
    private PendingDocument pendingDocument;
    private boolean documentPickerOpen;

    private static final class PendingDocument {
        final String id;
        final String filename;
        final String mimeType;
        final long size;
        final File stagingFile;
        final FileOutputStream output;
        final JavaScriptReplyProxy reply;
        long received;
        boolean closed;

        PendingDocument(String id, String filename, String mimeType, long size,
                        File stagingFile, FileOutputStream output, JavaScriptReplyProxy reply) {
            this.id = id;
            this.filename = filename;
            this.mimeType = mimeType;
            this.size = size;
            this.stagingFile = stagingFile;
            this.output = output;
            this.reply = reply;
        }

        void close() throws Exception {
            if (!closed) {
                closed = true;
                output.flush();
                output.close();
            }
        }

        void discard() {
            try { if (!closed) output.close(); } catch (Exception ignored) {}
            closed = true;
            if (stagingFile.exists()) stagingFile.delete();
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        appUpdateManager = AppUpdateManagerFactory.create(this);
        checkForPlayUpdate();

        getWindow().setStatusBarColor(Color.rgb(7, 40, 99));
        getWindow().setNavigationBarColor(Color.rgb(7, 40, 99));

        FrameLayout root = new FrameLayout(this);
        try {
            webView = new WebView(this);
        } catch (Throwable webViewFailure) {
            openBrowserFallback();
            finish();
            return;
        }

        root.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);

        try {
            configureWebView();

            if (savedInstanceState != null) {
                webView.restoreState(savedInstanceState);
            } else {
                Uri deepLink = getIntent() == null ? null : getIntent().getData();
                webView.loadUrl(isEdusentiaUri(deepLink) ? deepLink.toString() : HOME_URL);
            }
        } catch (Throwable runtimeFailure) {
            openBrowserFallback();
            finish();
        }
    }

    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setSupportZoom(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(true);
        settings.setSupportMultipleWindows(false);
        settings.setMediaPlaybackRequiresUserGesture(true);

        configureNativeDocumentSave();

        CookieManager cookieManager = CookieManager.getInstance();
        cookieManager.setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleNavigation(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return handleNavigation(Uri.parse(url));
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(view, request, error);
                if (request.isForMainFrame()) {
                    Toast.makeText(MainActivity.this,
                            "Unable to load Edusentia Enterprise Neon Edition. Check your internet connection and try again.",
                            Toast.LENGTH_LONG).show();
                }
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView webView,
                                             ValueCallback<Uri[]> callback,
                                             FileChooserParams fileChooserParams) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = callback;

                Intent chooserIntent;
                try {
                    chooserIntent = fileChooserParams.createIntent();
                } catch (Exception ignored) {
                    chooserIntent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                    chooserIntent.addCategory(Intent.CATEGORY_OPENABLE);
                    chooserIntent.setType("*/*");
                }

                try {
                    startActivityForResult(chooserIntent, FILE_CHOOSER_REQUEST);
                    return true;
                } catch (ActivityNotFoundException ex) {
                    filePathCallback = null;
                    Toast.makeText(MainActivity.this,
                            "No file picker is available on this device.",
                            Toast.LENGTH_LONG).show();
                    return false;
                }
            }
        });
    }

    private void configureNativeDocumentSave() {
        // WebMessageListener is origin-scoped and checks isMainFrame. Unlike
        // addJavascriptInterface, third-party iframes cannot request filesystem access.
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            return;
        }
        WebViewCompat.addWebMessageListener(webView, "EdusentiaAndroidDownloads",
                Collections.singleton("https://owusuduahephraim1.github.io"),
                (view, message, origin, isMainFrame, reply) -> {
                    if (!isMainFrame || origin == null
                            || !"https".equalsIgnoreCase(origin.getScheme())
                            || !"owusuduahephraim1.github.io".equalsIgnoreCase(origin.getHost())
                            || !isEdusentiaUri(Uri.parse(view.getUrl()))) return;
                    handleDocumentMessage(message, reply);
                });
    }

    private void respond(JavaScriptReplyProxy reply, String id, String status,
                         String filename, String message) {
        try {
            JSONObject response = new JSONObject();
            response.put("id", id);
            response.put("status", status);
            response.put("filename", filename == null ? "" : filename);
            response.put("message", message == null ? "" : message);
            reply.postMessage(response.toString());
        } catch (Exception ignored) {}
    }

    private void failDocument(String id, JavaScriptReplyProxy reply, String reason) {
        if (pendingDocument != null && pendingDocument.id.equals(id)) {
            pendingDocument.discard();
            pendingDocument = null;
        }
        respond(reply, id, "error", "", reason);
    }

    private void handleDocumentMessage(WebMessageCompat message, JavaScriptReplyProxy reply) {
        String id = "";
        try {
            JSONObject data = new JSONObject(message.getData());
            id = data.optString("id", "");
            if (id.length() == 0 || id.length() > 100) return;
            String type = data.optString("type", "");
            if ("begin".equals(type)) {
                if (pendingDocument != null || documentPickerOpen) {
                    respond(reply, id, "error", "", "Finish the current download before starting another.");
                    return;
                }
                long size = data.optLong("size", -1);
                if (size <= 0 || size > MAX_DOCUMENT_BYTES) {
                    respond(reply, id, "error", "", "Document exceeds the 64 MB save limit or is empty.");
                    return;
                }
                String filename = data.optString("filename", "document")
                        .replaceAll("[\\\\/<>:\"|?*\\x00-\\x1F]", "_");
                if (filename.length() == 0) filename = "document";
                if (filename.length() > 140) filename = filename.substring(0, 140);
                String mimeType = data.optString("mimeType", "application/octet-stream").split(";")[0];
                if (!mimeType.matches("[a-zA-Z0-9.+_-]+/[a-zA-Z0-9.+_-]+"))
                    mimeType = "application/octet-stream";
                File temp = File.createTempFile("edusentia-document-", ".tmp", getCacheDir());
                pendingDocument = new PendingDocument(id, filename, mimeType, size,
                        temp, new FileOutputStream(temp), reply);
                return;
            }
            if (pendingDocument == null || !pendingDocument.id.equals(id)) return;
            if ("chunk".equals(type)) {
                String chunk = data.optString("data", "");
                if (pendingDocument.closed || chunk.length() == 0 || chunk.length() > MAX_BASE64_CHUNK) {
                    failDocument(id, reply, "Invalid native document data.");
                    return;
                }
                byte[] decoded = Base64.decode(chunk, Base64.NO_WRAP);
                if (pendingDocument.received + decoded.length > pendingDocument.size) {
                    failDocument(id, reply, "Document length verification failed.");
                    return;
                }
                pendingDocument.output.write(decoded);
                pendingDocument.received += decoded.length;
            } else if ("finish".equals(type)) {
                pendingDocument.close();
                if (pendingDocument.received != pendingDocument.size) {
                    failDocument(id, reply, "Document transfer was incomplete.");
                    return;
                }
                Intent picker = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                picker.addCategory(Intent.CATEGORY_OPENABLE);
                picker.setType(pendingDocument.mimeType);
                picker.putExtra(Intent.EXTRA_TITLE, pendingDocument.filename);
                try {
                    documentPickerOpen = true;
                    startActivityForResult(picker, DOCUMENT_SAVE_REQUEST);
                } catch (Exception error) {
                    documentPickerOpen = false;
                    failDocument(id, reply, "Unable to open the Android Save dialog.");
                }
            } else if ("abort".equals(type)) {
                failDocument(id, reply, "Download cancelled.");
            }
        } catch (Exception error) {
            if (!id.isEmpty()) failDocument(id, reply, "Unable to prepare the document for saving.");
        }
    }

    private void finishNativeDocument(int resultCode, Intent data) {
        documentPickerOpen = false;
        final PendingDocument document = pendingDocument;
        pendingDocument = null;
        if (document == null) return;
        final Uri uri = data == null ? null : data.getData();
        if (resultCode != RESULT_OK || uri == null) {
            document.discard();
            respond(document.reply, document.id, "cancelled", "", "Save cancelled.");
            return;
        }
        documentIo.execute(() -> {
            String status = "saved", error = "";
            try (InputStream input = new FileInputStream(document.stagingFile);
                 OutputStream output = getContentResolver().openOutputStream(uri, "w")) {
                if (output == null) throw new Exception("Unable to open the selected destination.");
                byte[] buffer = new byte[64 * 1024];
                int len;
                while ((len = input.read(buffer)) != -1) output.write(buffer, 0, len);
                output.flush();
            } catch (Exception ex) {
                status = "error";
                error = "The device could not write the selected file.";
                try { getContentResolver().delete(uri, null, null); } catch (Exception ignored) {}
            } finally {
                document.discard();
            }
            final String savedStatus = status, savedError = error;
            runOnUiThread(() -> respond(document.reply, document.id, savedStatus,
                    document.filename, savedError));
        });
    }

    private void checkForPlayUpdate() {
        if (appUpdateManager == null) return;
        appUpdateManager.getAppUpdateInfo().addOnSuccessListener(info -> {
            if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
                    && info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                startImmediatePlayUpdate(info);
            }
        }).addOnFailureListener(error -> {
            // Sideloaded/internal APKs are allowed to continue normally.
        });
    }

    private void resumePlayUpdateIfNeeded() {
        if (appUpdateManager == null) return;
        appUpdateManager.getAppUpdateInfo().addOnSuccessListener(info -> {
            if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                startImmediatePlayUpdate(info);
            }
        }).addOnFailureListener(error -> {
            // Google Play update APIs are unavailable for non-Play installs.
        });
    }

    private void startImmediatePlayUpdate(AppUpdateInfo info) {
        try {
            appUpdateManager.startUpdateFlowForResult(
                    info,
                    this,
                    AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                    PLAY_UPDATE_REQUEST);
        } catch (Exception ignored) {
            // The hosted Neon application still remains available if the native update flow cannot start.
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumePlayUpdateIfNeeded();
    }

    private boolean handleNavigation(Uri uri) {
        if (uri == null || uri.getScheme() == null) {
            return false;
        }

        String scheme = uri.getScheme().toLowerCase(Locale.ROOT);
        if ("http".equals(scheme) || "https".equals(scheme)) {
            String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);

            if ("wa.me".equals(host) || host.endsWith(".whatsapp.com") || "api.whatsapp.com".equals(host)) {
                return openExternal(uri);
            }

            if ("owusuduahephraim1.github.io".equals(host) && uri.getPath() != null
                    && uri.getPath().startsWith("/Edusentia-Enterprise-Neon-Edition")) {
                return false;
            }

            return openExternal(uri);
        }

        if ("intent".equals(scheme)) {
            try {
                Intent intent = Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME);
                startActivity(intent);
                return true;
            } catch (Exception ignored) {
                return true;
            }
        }

        return openExternal(uri);
    }

    private boolean openExternal(Uri uri) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            startActivity(intent);
        } catch (ActivityNotFoundException ex) {
            Toast.makeText(this, "No application is available to open this link.", Toast.LENGTH_SHORT).show();
        }
        return true;
    }

    private void openBrowserFallback() {
        try {
            Intent browser = new Intent(Intent.ACTION_VIEW, Uri.parse(HOME_URL));
            startActivity(browser);
        } catch (ActivityNotFoundException ignored) {
            Toast.makeText(this,
                    "Edusentia Enterprise Neon Edition requires Android System WebView or a web browser.",
                    Toast.LENGTH_LONG).show();
        }
    }

    private boolean isEdusentiaUri(Uri uri) {
        if (uri == null || uri.getHost() == null) {
            return false;
        }
        String scheme = uri.getScheme();
        String host = uri.getHost().toLowerCase(Locale.ROOT);
        return "https".equalsIgnoreCase(scheme)
                && "owusuduahephraim1.github.io".equals(host)
                && uri.getPath() != null
                && uri.getPath().startsWith("/Edusentia-Enterprise-Neon-Edition");
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        Uri uri = intent.getData();
        if (isEdusentiaUri(uri) && webView != null) {
            webView.loadUrl(uri.toString());
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        if (webView != null) {
            webView.saveState(outState);
        }
        super.onSaveInstanceState(outState);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == DOCUMENT_SAVE_REQUEST) {
            finishNativeDocument(resultCode, data);
            return;
        }
        if (requestCode == FILE_CHOOSER_REQUEST && filePathCallback != null) {
            Uri[] results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
            filePathCallback.onReceiveValue(results);
            filePathCallback = null;
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (pendingDocument != null) {
            pendingDocument.discard();
            pendingDocument = null;
        }
        documentIo.shutdown();
        if (webView != null) {
            webView.stopLoading();
            webView.setWebChromeClient(null);
            webView.setWebViewClient(null);
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
