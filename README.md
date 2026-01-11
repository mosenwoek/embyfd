自用emby反代，通过cf的snippets部署

回到 Cloudflare 面板，进入 Rules -> Snippets。
 看下面的 Snippet Rules 列表。
 点击右边的 Edit（编辑）。
 检查 Expression (表达式)：

    错误写法：URI Path contains ... (这样写只拦截了特定路径，网页首页 / 没被拦截，直接去连假 IP 了，必挂)。
    正确写法：必须拦截整个域名。
    请把表达式改成：
        Field: Hostname
        Operator: equals
        Value: emby.你的域名.com (你的完整反代域名)
