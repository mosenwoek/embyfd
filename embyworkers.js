// 反代目标地址
const upstream = 'xx.com'
// 目标端口
const upstream_port = 443
// 是否开启 HTTPS
const upstream_path = 'https://'

// 移动端/特定客户端重定向逻辑（防止不必要的路径问题）
const mobile_redirect = false

addEventListener('fetch', event => {
    event.respondWith(fetchAndApply(event.request));
})

async function fetchAndApply(request) {
    const region = request.headers.get('cf-ipcountry').toUpperCase();
    const ip_address = request.headers.get('cf-connecting-ip');
    const user_agent = request.headers.get('user-agent');

    let response = null;
    let url = new URL(request.url);
    let url_hostname = url.hostname;

    // 修改请求 URL 指向目标服务器
    url.protocol = upstream_path;
    url.host = upstream;
    url.port = upstream_port;

    let method = request.method;
    let request_headers = request.headers;
    let new_request_headers = new Headers(request_headers);

    // 核心：设置 Host 头部，欺骗目标服务器
    new_request_headers.set('Host', upstream);
    new_request_headers.set('Referer', upstream_path + upstream);

    // 发起请求
    let original_response = await fetch(url.href, {
        method: method,
        headers: new_request_headers,
        body: request.body
    })

    let response_headers = original_response.headers;
    let new_response_headers = new Headers(response_headers);
    let status = original_response.status;

    // 如果需要，可以在这里修改返回头，例如解决跨域问题
    // new_response_headers.set('access-control-allow-origin', '*');
    // new_response_headers.set('access-control-allow-credentials', true);

    response = new Response(original_response.body, {
        status,
        headers: new_response_headers
    })

    return response;
}
