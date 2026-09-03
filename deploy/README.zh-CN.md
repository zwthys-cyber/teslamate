# TeslaMate 中国区部署

本目录从当前 fork 源码构建 TeslaMate 和 Grafana。运行时密钥保存在未纳入 Git 的
`deploy/.env` 中，数据保存在 Docker 命名卷中。

## 管理命令

在仓库根目录执行：

```bash
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
docker compose --env-file deploy/.env -f deploy/compose.yaml logs -f teslamate
docker compose --env-file deploy/.env -f deploy/compose.yaml restart
```

Web 服务仅监听服务器本机。可通过 SSH 隧道访问：

```bash
ssh -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 user@server
```

随后访问 TeslaMate `http://127.0.0.1:4000` 和 Grafana
`http://127.0.0.1:3000`。Grafana 初始账户和密码均为 `admin`，首次登录后应立即修改。

中国区车辆登录后，若 Streaming API 返回 `403` 或车辆持续离线，请在 TeslaMate 的
车辆设置中关闭 Streaming API，使用轮询采集。

## 升级

升级前先备份数据库：

```bash
docker compose --env-file deploy/.env -f deploy/compose.yaml exec -T database \
  pg_dump -U teslamate teslamate > teslamate.bck
```

同步官方仓库并推送到 fork：

```bash
git fetch upstream
git checkout main
git merge --ff-only upstream/main
git push origin main
```

确认新提交后，把 `deploy/.env` 中的 `TESLAMATE_VERSION` 更新为新提交的短哈希，再执行：

```bash
docker compose --env-file deploy/.env -f deploy/compose.yaml build --pull
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d
```

不要删除 Docker 卷，也不要更改既有 `TM_ENCRYPTION_KEY`，否则会丢失数据或无法解密
已保存的 Tesla API 令牌。
