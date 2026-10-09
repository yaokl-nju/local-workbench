"""Local-only manual WebKit fixture. Never contacts a platform or uses real accounts."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import sys
import time

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == "/download":
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="ask-fixture.txt"')
            self.end_headers()
            self.wfile.write(b"LocalNotes isolated download test\n")
            return
        provider = self.path.strip("/").split("/")[0] or "fixture"
        html = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
        <title>随时问测试 · PROVIDER</title>
        <style>body{font:16px system-ui;padding:24px;color:#222;background:#fff}button,a,input{margin:8px;padding:8px}textarea{display:block;width:90%;height:90px;margin:16px 0}section{margin:16px 0}</style>
        <h1>随时问测试 · PROVIDER</h1>
        <p id="visits"></p><p id="cookie"></p><p id="storage"></p>
        <label for="draft">聊天草稿</label><textarea id="draft" aria-label="聊天草稿"></textarea>
        <button onclick="document.cookie='fixture=PROVIDER;max-age=86400;path=/';localStorage.setItem('fixture','PROVIDER');location.reload()">保存模拟登录</button>
        <button onclick="window.open('/popup','login','width=600,height=600')">打开登录弹窗</button>
        <a href="/PROVIDER/next">下一页</a><a href="/download">下载附件</a>
        <section><label>上传附件 <input aria-label="上传附件" type="file" onchange="document.getElementById('picked').textContent=this.files[0]?.name||'未选择'"></label><span id="picked"></span></section>
        <button onclick="location.href='http://127.0.0.1:65530/unavailable'">触发网络失败</button>
        <button onclick="document.getElementById('sent').textContent=document.getElementById('draft').value">发送测试消息</button><p id="sent"></p>
        <p>查找目标：测试文字</p><p style="margin-top:1100px">滚动底部标记</p>
        <script>
        let visits=Number(sessionStorage.getItem('visits')||0)+1;sessionStorage.setItem('visits',visits);
        document.getElementById('visits').textContent='页面加载次数：'+visits;
        document.getElementById('cookie').textContent='Cookie：'+(document.cookie||'空');
        document.getElementById('storage').textContent='Storage：'+(localStorage.getItem('fixture')||'空');
        if(location.pathname==='/popup'){document.body.innerHTML=`<h1>模拟登录弹窗</h1><p>共享Cookie：${document.cookie}</p><button onclick="window.opener.document.getElementById('sent').textContent='登录回调成功';window.close()">完成登录回调</button>`}
        </script></html>""".replace("PROVIDER", provider)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(html.encode())

if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 0), Handler)
    Path(sys.argv[1]).write_text(json.dumps({"origin": f"http://127.0.0.1:{server.server_port}"}))
    print(f"Fixture ready on loopback port {server.server_port}", flush=True)
    server.serve_forever()
