# 行程和充电接口约定

第二轮 iOS 客户端需要配套本轮后端。旧服务器缺少 `pagination` 或 `car_id` 时，
App 提示升级服务器，不会把截断的历史记录误报为全部记录。

所有接口以 `/api/mobile/v1` 为前缀，使用已有 Bearer 令牌。
这仍然是单个自托管实例的全车辆访问令牌；`car_id` 用于选择车辆，不是多账户授权机制。

## 历史列表

- `GET /drives`
- `GET /charging`

| 参数 | 约定 |
| --- | --- |
| `car_id` | 正整数；iOS 必填。为兼容旧调用，服务端在未提供时选择首辆车。 |
| `limit` | 1–500，默认 100，iOS 每页 50；非法值返回 400。 |
| `from` | 可选，带时区的 ISO 8601 时间，包含该时间。 |
| `to` | 可选，带时区的 ISO 8601 时间，不包含该时间；必须晚于 `from`。 |
| `cursor` | 上一页返回的非空 `next_cursor`，不可在切换车辆、服务器或日期筛选后复用。 |

按 `start_date DESC, id DESC` 排序，筛选按记录开始时间判断。
App 的结束日期包含当天，使用手机日历计算次日零点后再转换为 UTC；不使用固定 24 小时拼接日期。

```json
{
  "data": [],
  "pagination": {"next_cursor": null}
}
```

`next_cursor: null` 表示没有下一页。游标是服务端生成的不透明字符串，客户端原样传回。
记录新增不会把已翻过的页推移；刷新从第一页重新开始。记录在翻页期间被删除或修正时，
列表不是数据库快照，重新刷新可获取最新结果。

所有行程和充电记录都包含 `id`、`car_id`、`start_date`，`end_date` 可为 null（进行中）。
时间允许整秒或小数秒。其他测量数据、地点和费用可以为空。

## 详情

- `GET /drives/:id?car_id=...`
- `GET /charging/:id?car_id=...`

App 必须发送当前车辆 ID；记录不属于该车时返回 404。服务端仍允许旧调用省略 `car_id`。
返回 `{"data": {...}}`，行程附带 `positions`，充电附带 `samples`。

为限制手机内存和传输量，SQL 按时间及采样 ID 排序后均匀抽样，最多 2000 点，保留首尾。
详情包含 `sampling: {total, returned, downsampled}`。空采样返回空数组和零计数。
路线可能被简化，充电曲线的短时峰值可能被抽样略过；App 会提示该限制。
这项响应上限不意味着数据库查询时间是常数。

单位：里程 km、速度 km/h、温度 °C、功率 kW、电量 kWh。
`cost: null` 表示未记录，0 表示记录金额为零。服务器尚未提供币种，不推断人民币或其他币种。

## 错误

- 400：`invalid_car_id`、`invalid_id`、`invalid_history_parameters`
- 401：`unauthorized`
- 404：`vehicle_not_found`、`record_not_found`

响应格式为 `{"error":"错误代码"}`。移动接口响应使用 `Cache-Control: no-store`。

## 数据库升级

迁移 `20260905090000_index_mobile_history` 为行程和充电增加
`(car_id, start_date, id)` 索引。使用并发建索引，不删除数据；迁移应由单个部署进程执行。
升级部署前保留数据库备份，完成迁移后再发布本轮客户端。
