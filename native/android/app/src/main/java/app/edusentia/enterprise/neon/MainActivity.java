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

    private WebView webView;
    private AppUpdateManager appUpdateManager;
    private ValueCallback<Uri[]> filePathCallback;

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
