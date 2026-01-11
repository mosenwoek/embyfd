export default {
  async fetch(request) {
    // ---------------- 配置区域 ----------------
    // 源站域名 (你的公益服地址)
    const UPSTREAM_DOMAIN = "xx.com";
    // 源站完整 URL (带协议)
    const UPSTREAM_URL = "https://xx.com";
    // ----------------------------------------

    const url = new URL(request.url);

    // === 逻辑1：视频播放 -> 302 直连 ===
    // 如果是视频流，直接跳过去，不走 CF 流量
    if (
      url.pathname.includes("/Videos/") || 
      url.pathname.includes("/Audio/") ||
      (url.pathname.includes("/Items/") && url.pathname.includes("/Download"))
    ) {
      // 这里的逻辑是：让你的播放器直接去连 xx.com
      const redirectUrl = `${UPSTREAM_URL}${url.pathname}${url.search}`;
      return Response.redirect(redirectUrl, 302);
    }

    // === 逻辑2：网页界面 -> 伪装反代 ===
    // 如果不是视频，我们需要帮用户去取网页
    
    // 1. 构建去往源站的 URL
    const newUrl = new URL(UPSTREAM_URL);
    newUrl.pathname = url.pathname;
    newUrl.search = url.search;

    // 2. 创建新请求
    const newRequest = new Request(newUrl.toString(), {
      method: request.method,
      headers: request.headers,
      body: request.body,
      redirect: "follow"
    });

    // 3. 【关键步骤】强制修改 Host 头部
    // 如果不改这个，gm.yezi.my 会拒绝你的连接 (报 404 或 403)
    newRequest.headers.set("Host", UPSTREAM_DOMAIN);

    // 4. 清理 CF 特有头部，防止回环报错
    newRequest.headers.delete("cf-connecting-ip");
    newRequest.headers.delete("cf-ipcountry");

    // 5. 发起请求并返回结果
    try {
      return await fetch(newRequest);
    } catch (e) {
      return new Response(`Snippet Error: ${e.message}`, { status: 502 });
    }
  },
};
