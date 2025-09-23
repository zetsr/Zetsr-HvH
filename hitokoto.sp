#include <sourcemod>
#include <colors>
#include <steamworks>

#pragma semicolon 1
#pragma newdecls required

// -------- 配置（改这里就行） --------
// API endpoint（宏形式避免全局数组初始化问题）
#define API_ENDPOINT "https://v1.hitokoto.cn/"
// 聊天输出格式（第一个 %s = hitokoto，第二个 %s = from）
#define G_CHAT_FORMAT "{grey}新曙光 - {default}『%s』—— %s"

// JSON 键常量（宏）
#define KEY_HITOKOTO "\"hitokoto\":\""
#define KEY_FROM     "\"from\":\""

// -------------------------------------

// 全局变量用于缓存响应和标志位
char g_sHitokoto[512];
char g_sFrom[256];
bool g_bResponseReady = false;
bool g_bTimerFired = false;

public Plugin myinfo = {
    name = "Hitokoto Quote",
    author = "Grok (modified)",
    description = "Displays a quote from v1.hitokoto.cn at round start with 1s delay (no disk logs)",
    version = "2.2",
    url = ""
};

public void OnPluginStart() {
    PrintToServer("[Hitokoto] Plugin starting...");
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    PrintToServer("[Hitokoto] Hooked round_start -> Event_RoundStart");
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    PrintToServer("[Hitokoto] Round start event triggered, resetting flags and creating HTTP GET to %s", API_ENDPOINT);

    // 重置标志位和缓存
    g_bResponseReady = false;
    g_bTimerFired = false;
    g_sHitokoto[0] = '\0';
    g_sFrom[0] = '\0';

    // 启动2.0秒计时器
    CreateTimer(2.0, Timer_PrintQuote, _, TIMER_FLAG_NO_MAPCHANGE);

    // 立即发送HTTP请求
    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, API_ENDPOINT);
    if (request == null) {
        PrintToServer("[Hitokoto] Failed to create HTTP request (null handle).");
        return;
    }

    SteamWorks_SetHTTPRequestHeaderValue(request, "Accept", "application/json");
    SteamWorks_SetHTTPRequestContextValue(request, 0);
    SteamWorks_SetHTTPCallbacks(request, OnAPIResponse);

    if (!SteamWorks_SendHTTPRequest(request)) {
        PrintToServer("[Hitokoto] Failed to send HTTP request");
        CloseHandle(request);
    } else {
        PrintToServer("[Hitokoto] HTTP request sent successfully");
    }
}

public void OnAPIResponse(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data) {
    PrintToServer("[Hitokoto] API response received. Failure: %d, RequestSuccessful: %d, StatusCode: %d",
                  bFailure, bRequestSuccessful, eStatusCode);

    if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK) {
        PrintToServer("[Hitokoto] Request failed or bad status code: %d", eStatusCode);
        CloseHandle(request);
        return;
    }

    // 获取响应体（回调）
    SteamWorks_GetHTTPResponseBodyCallback(request, OnResponseBodyReceived, data);
    CloseHandle(request);
}

public void OnResponseBodyReceived(const char[] data, any value) {
    // 只打印前200字以免刷屏
    PrintToServer("[Hitokoto] Response body callback. Data: %.200s", data);

    if (data[0] == '\0') {
        PrintToServer("[Hitokoto] Response body is empty");
        return;
    }

    if (!ExtractHitokotoFromJSON(data, g_sHitokoto, sizeof(g_sHitokoto), g_sFrom, sizeof(g_sFrom))) {
        PrintToServer("[Hitokoto] Failed to extract hitokoto/from from JSON");
        return;
    }

    TrimWhitespace(g_sHitokoto);
    TrimWhitespace(g_sFrom);

    if (g_sHitokoto[0] != '\0') {
        g_bResponseReady = true;
        PrintToServer("[Hitokoto] Response cached successfully");

        // 如果计时器已触发，立即打印
        if (g_bTimerFired) {
            PrintQuote();
        }
    } else {
        PrintToServer("[Hitokoto] hitokoto field empty, not setting ready");
    }
}

public Action Timer_PrintQuote(Handle timer) {
    g_bTimerFired = true;
    PrintToServer("[Hitokoto] 1s timer fired");

    // 如果响应已就绪，立即打印
    if (g_bResponseReady) {
        PrintQuote();
    }

    return Plugin_Stop;
}

void PrintQuote() {
    CPrintToChatAll(G_CHAT_FORMAT, g_sHitokoto, g_sFrom);
    PrintToServer("[Hitokoto] Printed to chat: \"%s\" —— %s", g_sHitokoto, g_sFrom);
}

/**
 * 从 JSON 响应中提取 hitokoto 和 from 字段（手工解析）
 * 返回 true = 成功（至少取得 hitokoto 字段），false = 失败
 */
bool ExtractHitokotoFromJSON(const char[] json, char[] outHitokoto, int hitokotoMax, char[] outFrom, int fromMax) {
    int len = strlen(json);

    // 查找 hitokoto
    int pos = StrContains(json, KEY_HITOKOTO);
    if (pos == -1) {
        PrintToServer("[Hitokoto] JSON parse error: 'hitokoto' not found");
        return false;
    }
    int start = pos + strlen(KEY_HITOKOTO);

    // 找结束的双引号（跳过转义 \")
    int i = start;
    while (i < len) {
        if (json[i] == '"' && (i == 0 || json[i-1] != '\\')) break;
        i++;
    }
    if (i >= len) {
        PrintToServer("[Hitokoto] JSON parse error: closing quote for hitokoto not found");
        return false;
    }
    int copyLen = i - start;
    if (copyLen > hitokotoMax - 1) copyLen = hitokotoMax - 1;
    for (int j = 0; j < copyLen; j++) {
        outHitokoto[j] = json[start + j];
    }
    outHitokoto[copyLen] = '\0';

    // 查找 from；若没有则设为 "未知"
    pos = StrContains(json, KEY_FROM);
    if (pos == -1) {
        strcopy(outFrom, fromMax, "未知");
        return true;
    }
    start = pos + strlen(KEY_FROM);
    i = start;
    while (i < len) {
        if (json[i] == '"' && (i == 0 || json[i-1] != '\\')) break;
        i++;
    }
    if (i >= len) {
        strcopy(outFrom, fromMax, "未知");
        return true;
    }
    copyLen = i - start;
    if (copyLen > fromMax - 1) copyLen = fromMax - 1;
    for (int j = 0; j < copyLen; j++) {
        outFrom[j] = json[start + j];
    }
    outFrom[copyLen] = '\0';

    return true;
}

/** 简单修剪两端空白（改名以避免与其他库冲突） */
void TrimWhitespace(char[] s) {
    int len = strlen(s);
    int start = 0;
    while (start < len && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r')) start++;

    if (start > 0) {
        int i = 0;
        while (start + i <= len) { // 包含终止符
            s[i] = s[start + i];
            i++;
        }
        len = strlen(s);
    }

    while (len > 0 && (s[len-1] == ' ' || s[len-1] == '\t' || s[len-1] == '\n' || s[len-1] == '\r')) {
        s[len-1] = '\0';
        len--;
    }
}