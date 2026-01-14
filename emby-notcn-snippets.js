const FIXED_EMBY_ORIGIN = ''; // 例如：https://emby.example.com
const UPSTREAM_BASE_PATH = '/emby';

export default {
  async fetch(request) {
    const start = Date.now();
    const url = new URL(request.url);

    const clientIp =
      request.headers.get('CF-Connecting-IP') 
      request.headers.get('X-Forwarded-For') 
      'unknown';

    const country = request.cf?.country  'unknown';
    const colo = request.cf?.colo  'unknown';

    // ================== 中国大陆限制 ==================
    if (country !== 'CN') {
      return new Response(
        `访问受限
仅允许中国大陆直连访问
请关闭代理或将域名加入直连规则后重试

IP: ${clientIp}
地区: ${country}
CF 节点: ${colo}`,
        {
          status: 403,
          headers: {
            'Content-Type': 'text/plain; charset=UTF-8',
          },
        }
      );
    }

    // ================== 根路径状态页 ==================
    if (url.pathname === '/' || url.pathname === '') {
      let upstreamCost = -1;

      try {
        const pingStart = Date.now();
        await fetch(
          FIXED_EMBY_ORIGIN + UPSTREAM_BASE_PATH + '/System/Info/Public',
          { method: 'HEAD', cf: { cacheTtl: 0 } }
        );
        upstreamCost = Date.now() - pingStart;
      } catch (_) {}

      const totalCost = Date.now() - start;

      return new Response(
        `Emby Proxy OK

IP: ${clientIp}
Country: ${country}
Edge: ${colo}
总耗时: ${totalCost} ms
上游延迟: ${upstreamCost >= 0 ? upstreamCost + ' ms' : '测试失败'}

推荐使用主流 Emby 客户端观看：
Yamby / SenPlayer / Hills / 小幻影视`,
        {
          headers: {
            'Content-Type': 'text/plain; charset=UTF-8',
          },
        }
      );
    }

    // ================== 构造上游 URL（自动补 /emby） ==================
    const upstream = new URL(FIXED_EMBY_ORIGIN);

    if (url.pathname.startsWith(UPSTREAM_BASE_PATH)) {
      upstream.pathname = url.pathname;
    } else {
      upstream.pathname =
        UPSTREAM_BASE_PATH +
        (url.pathname.startsWith('/') ? url.pathname : '/' + url.pathname);
    }

    upstream.search = url.search;

    // ================== WebSocket 透传 ==================
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      return fetch(upstream.toString(), request);
    }

    // ================== 反代请求 ==================
    const headers = new Headers(request.headers);
    headers.set('Host', upstream.host);

    const upstreamReq = new Request(upstream.toString(), {
      method: request.method,
      headers,
      body: request.body,
      redirect: 'follow',
    });

    const res = await fetch(upstreamReq);

    return new Response(res.body, {
      status: res.status,
      statusText: res.statusText,
      headers: res.headers,
    });
  },
};
