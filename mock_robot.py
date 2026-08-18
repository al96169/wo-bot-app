#!/usr/bin/env python3
"""
Mock robot — 完整匹配 web-debug 绑定协议
支持: display, tts, gimbal, share_code, password
支持全部状态查询和命令响应
"""
import asyncio, json, sys, random, hashlib, time
try:
    import websockets
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
    import websockets

# 绑定状态
bindings = {}  # requestToken → {method, code, sequence, clientId}
bound_clients = {}  # clientId → {clientToken, robotId}

PORT = 18768

# 模拟的舞蹈列表
DANCES = [
    {"id": "dance_001", "name": "小苹果", "duration": 180, "difficulty": "easy"},
    {"id": "dance_002", "name": "最炫民族风", "duration": 200, "difficulty": "medium"},
    {"id": "dance_003", "name": "江南style", "duration": 220, "difficulty": "hard"},
]

# 模拟的音乐列表
MUSIC = [
    {"id": "song_001", "title": "晴天", "artist": "周杰伦", "duration": 240},
    {"id": "song_002", "title": "稻香", "artist": "周杰伦", "duration": 223},
]

# 模拟的软件列表
SOFTWARE = [
    {"id": "core", "name": "核心服务", "version": "1.0.0", "installed": True},
    {"id": "vision", "name": "视觉模块", "version": "0.9.0", "installed": True},
]

# 模拟的系统日志（line_no 从 100 开始，模拟已有多条）
def _mock_logs():
    logs = []
    for i in range(30):
        line_no = 101 + i
        if i % 5 == 0:
            level, source, message = "info", "wo-bot-control", f"服务启动完成 v1.0.0 (line {line_no})"
        elif i % 5 == 1:
            level, source, message = "info", "camera", f"摄像头 {i % 2} 初始化成功"
        elif i % 5 == 2:
            level, source, message = "warn", "system", f"CPU 温度偏高: 65°C (line {line_no})"
        elif i % 5 == 3:
            level, source, message = "info", "motion", f"运动指令已处理 vx=0 vy=0 vz=0"
        else:
            level, source, message = "debug", "websocket", f"心跳保活 OK (line {line_no})"
        logs.append({
            "line_no": line_no,
            "timestamp": f"2026-08-18 {10 + i // 6:02d}:{30 + (i % 6) * 5:02d}:00",
            "level": level,
            "source": source,
            "message": message,
        })
    return logs

def MOCK_LOGS_RESPONSE(mode, limit, level, since_line=0, before_line=0):
    all_logs = _mock_logs()
    # 级别过滤（服务端用 "warning"，前端转 "warn"）
    if level and level != "all":
        lv = "warning" if level == "warn" else level
        all_logs = [l for l in all_logs if l["level"] == lv]
    if mode == "tail":
        logs = all_logs[-limit:]
        return {"mode": "tail", "logs": logs, "total_lines": len(all_logs), "next_since": logs[-1]["line_no"] if logs else 0, "has_more": len(all_logs) > limit}
    if mode == "since":
        # 返回 line_no 之后的日志
        logs = [l for l in all_logs if l["line_no"] > since_line][-limit:]
        return {"mode": "since", "logs": logs, "next_since": logs[-1]["line_no"] if logs else since_line, "has_more": False}
    if mode == "before":
        # 返回 line_no 之前的日志
        logs = [l for l in all_logs if l["line_no"] < before_line][-limit:]
        return {"mode": "before", "logs": logs, "has_more": False}
    return {"mode": "tail", "logs": [], "has_more": False}

async def handler(websocket):
    addr = websocket.remote_address
    print(f"[+] Connected: {addr}")
    client_id = ""
    is_bound = False

    # 检查 URL 参数中是否有凭证
    path = websocket.request.path if hasattr(websocket.request, 'path') else str(websocket.path)
    if 'clientToken=' in path:
        # 已绑定客户端，直接发 connected
        is_bound = True
        await websocket.send(json.dumps({
            "type": "connected",
            "data": {
                "name": "MockRobot",
                "version": "1.0.0",
                "features": ["move", "camera", "gimbal", "dance", "music", "software"],
                "robot_id": "mock-robot-001"
            }
        }))
        print("[>] connected (auto-auth)")
    else:
        # 未绑定，发送 auth_required
        await websocket.send(json.dumps({
            "type": "auth_required",
            "methods": ["display", "tts", "gimbal"]
        }))
        print("[>] auth_required (display, tts, gimbal)")

    async for msg in websocket:
        try:
            data = json.loads(msg)
            msg_type = data.get("type", "")
            print(f"[<] {msg_type}")

            # ===== 认证绑定流程 =====
            if msg_type == "bind_request":
                rt = data.get("requestToken", "")
                method = data.get("method", "")
                client_id = data.get("clientId", "unknown")
                
                if method in ("display", "tts"):
                    code = ''.join(random.choices('0123456789', k=6 if method == "display" else 4))
                    bindings[rt] = {"method": method, "code": code, "clientId": client_id}
                    
                    await websocket.send(json.dumps({
                        "type": "bind_request_ack",
                        "requestToken": rt,
                        "method": method,
                    }))
                    await websocket.send(json.dumps({
                        "type": "bind_challenge",
                        "requestToken": rt,
                        "method": method,
                        "codeHint": code,
                    }))
                    print(f"[>] bind_request_ack + bind_challenge (method={method}, code={code})")
                
                elif method == "gimbal":
                    # 生成随机方向序列
                    dirs = ["up", "down", "left", "right"]
                    sequence = [random.choice(dirs) for _ in range(4)]
                    bindings[rt] = {"method": method, "sequence": sequence, "clientId": client_id}
                    
                    await websocket.send(json.dumps({
                        "type": "bind_request_ack",
                        "requestToken": rt,
                        "method": method,
                    }))
                    # 模拟云台转动（不发 codeHint，让客户端观察）
                    print(f"[>] bind_request_ack (gimbal, sequence={sequence})")
                
                else:
                    await websocket.send(json.dumps({
                        "type": "bind_request_ack",
                        "requestToken": rt,
                        "method": method,
                    }))

            elif msg_type == "bind_verify":
                rt = data.get("requestToken", "")
                binding = bindings.get(rt)
                
                if not binding:
                    await websocket.send(json.dumps({"type": "bind_failed", "data": {"error": "无效的 requestToken"}}))
                    continue
                
                if binding["method"] in ("display", "tts"):
                    code = data.get("randomCode", "")
                    if code == binding["code"]:
                        await _send_bind_success(websocket, binding["clientId"])
                        is_bound = True
                    else:
                        await websocket.send(json.dumps({
                            "type": "bind_failed",
                            "data": {"error": f"验证码不匹配", "attempts": 1}
                        }))
                        print(f"[>] bind_failed (got={code}, expected={binding['code']})")
                
                elif binding["method"] == "gimbal":
                    sequence = data.get("sequence", [])
                    if sequence == binding["sequence"]:
                        await _send_bind_success(websocket, binding["clientId"])
                        is_bound = True
                    else:
                        await websocket.send(json.dumps({
                            "type": "bind_failed",
                            "data": {"error": "方向序列不匹配", "attempts": 1}
                        }))
                        print(f"[>] bind_failed (got={sequence}, expected={binding['sequence']})")

            elif msg_type == "bind_share_use":
                share_code = data.get("shareCode", "")
                client_id = data.get("clientId", "unknown")
                # 模拟分享码验证（任何 6 位码都通过）
                if len(share_code) == 6:
                    await _send_bind_success(websocket, client_id)
                    is_bound = True
                else:
                    await websocket.send(json.dumps({"type": "bind_failed", "data": {"error": "无效的分享码"}}))

            elif msg_type == "bind_password":
                password = data.get("password", "")
                if password == "123456":  # mock 密码
                    await _send_bind_success(websocket, data.get("clientId", "unknown"))
                    is_bound = True
                else:
                    await websocket.send(json.dumps({"type": "bind_failed", "data": {"error": "密码错误"}}))

            elif msg_type == "auth":
                # 已绑定客户端的自动认证
                cid = data.get("clientId", "")
                token = data.get("clientToken", "")
                if cid in bound_clients and bound_clients[cid]["clientToken"] == token:
                    await websocket.send(json.dumps({
                        "type": "connected",
                        "data": {"name": "MockRobot", "version": "1.0.0", "features": ["move", "camera", "gimbal"]}
                    }))
                    is_bound = True
                else:
                    await websocket.send(json.dumps({"type": "auth_required", "methods": ["display", "tts", "gimbal"]}))

            # ===== 已连接后的命令 =====
            elif is_bound or msg_type in ("ping", "get_status"):
                if msg_type == "ping":
                    await websocket.send(json.dumps({"type": "pong"}))

                elif msg_type == "get_status":
                    await websocket.send(json.dumps({
                        "type": "status",
                        "data": {
                            "battery": 85.0, "cpu_temp": 42.0, "speed": 0.5, "mode": "idle",
                            "wifi_signal": -45, "uptime": 3600, "cpuUsage": 30.0,
                            "memoryUsage": 45.0, "diskUsage": 60.0, "batteryCharging": False,
                            "batteryLevel": 85.0, "wifiSSID": "MockWiFi", "ip": "192.168.1.100",
                            "model": "MockRobot v1", "version": "1.0.0"
                        }
                    }))

                elif msg_type == "motion":
                    v = data.get("payload", data)
                    print(f"    motion: vx={v.get('v_x')} vy={v.get('v_y')} vz={v.get('v_z')}")

                elif msg_type == "motion_stop":
                    print("    STOP")

                elif msg_type == "gimbal":
                    p = data.get("payload", data)
                    print(f"    gimbal: {p}")
                    await websocket.send(json.dumps({
                        "type": "gimbal_status",
                        "data": {"pan": p.get("pan", 90), "tilt": p.get("tilt", 90)}
                    }))

                elif msg_type == "gimbal_move":
                    p = data.get("payload", data)
                    await websocket.send(json.dumps({
                        "type": "gimbal_status",
                        "data": {"pan": p.get("pan", 90), "tilt": p.get("tilt", 90)}
                    }))

                elif msg_type == "get_module_list":
                    await websocket.send(json.dumps({
                        "type": "module_list",
                        "data": {"modules": [{"id": "core", "name": "核心", "active": True}]}
                    }))

                elif msg_type == "get_service_status":
                    await websocket.send(json.dumps({
                        "type": "service_status",
                        "data": {"services": [{"id": "web", "name": "Web服务", "active": True}]}
                    }))

                elif msg_type == "dance_list":
                    await websocket.send(json.dumps({"type": "dance_list", "data": {"dances": DANCES}}))

                elif msg_type == "dance_play":
                    await websocket.send(json.dumps({"type": "dance_status", "data": {"status": "playing", "id": data.get("danceId"), "progress": 0}}))

                elif msg_type == "dance_stop":
                    await websocket.send(json.dumps({"type": "dance_status", "data": {"status": "stopped"}}))

                elif msg_type == "music_list":
                    await websocket.send(json.dumps({"type": "music_list", "data": {"songs": MUSIC}}))

                elif msg_type == "music_play":
                    await websocket.send(json.dumps({"type": "music_status", "data": {"status": "playing", "song": MUSIC[0]}}))

                elif msg_type == "music_pause":
                    await websocket.send(json.dumps({"type": "music_status", "data": {"status": "paused"}}))

                elif msg_type == "music_set_volume":
                    vol = data.get("volume", 50)
                    await websocket.send(json.dumps({"type": "music_volume", "data": {"volume": vol}}))

                elif msg_type == "camera_capture":
                    await websocket.send(json.dumps({"type": "camera_capture_result", "data": {"file_name": "photo_001.jpg"}}))

                elif msg_type == "camera_record":
                    action = data.get("action", "start")
                    await websocket.send(json.dumps({"type": "camera_record_result", "data": {"action": action}}))

                elif msg_type == "camera_media_list":
                    await websocket.send(json.dumps({
                        "type": "camera_media_list_result",
                        "data": {"items": [], "page": 1, "total": 0, "has_more": False}
                    }))

                elif msg_type == "software_list":
                    await websocket.send(json.dumps({"type": "software_list", "data": {"software": SOFTWARE}}))

                elif msg_type == "software_available":
                    await websocket.send(json.dumps({
                        "type": "software_available",
                        "data": {"software": [{"id": "voice", "name": "语音模块", "version": "1.0.0", "installed": False}]}
                    }))

                elif msg_type == "wifi_scan":
                    await websocket.send(json.dumps({
                        "type": "wifi_scan_result",
                        "data": {"networks": [{"ssid": "TestWiFi", "signal": -50, "security": "WPA2"}]}
                    }))

                elif msg_type == "get_power_policy":
                    await websocket.send(json.dumps({
                        "type": "power_policy_status",
                        "data": {"idle_timeout": 300, "auto_shutdown": True}
                    }))

                elif msg_type == "config_get":
                    await websocket.send(json.dumps({"type": "config_get_ack", "data": {"key": data.get("key"), "value": "default"}}))

                elif msg_type == "config_set":
                    await websocket.send(json.dumps({"type": "config_set_ack", "data": {"success": True}}))

                elif msg_type == "exec":
                    await websocket.send(json.dumps({"type": "exec_result", "data": {"exit_code": 0, "output": "ok"}}))

                elif msg_type == "logs":
                    # 模拟系统日志 — 匹配 web-debug logs 协议
                    mode = data.get("mode", "tail") if isinstance(data, dict) else "tail"
                    limit = int(data.get("limit", 200)) if isinstance(data, dict) else 200
                    level = data.get("level", "") if isinstance(data, dict) else ""
                    since_line = int(data.get("since_line", 0)) if isinstance(data, dict) else 0
                    before_line = int(data.get("before_line", 0)) if isinstance(data, dict) else 0
                    await websocket.send(json.dumps({
                        "type": "logs",
                        "data": MOCK_LOGS_RESPONSE(mode, limit, level, since_line, before_line)
                    }))

        except json.JSONDecodeError:
            print(f"[!] bad json: {msg[:100]}")
        except Exception as e:
            print(f"[!] error: {e}")

    print(f"[-] Disconnected: {addr}")


async def _send_bind_success(websocket, client_id):
    client_token = hashlib.sha256(f"{client_id}_mock".encode()).hexdigest()[:32]
    bound_clients[client_id] = {"clientToken": client_token, "robotId": "mock-robot-001"}
    
    await websocket.send(json.dumps({
        "type": "bind_success",
        "data": {
            "robotId": "mock-robot-001",
            "clientId": client_id,
            "clientToken": client_token,
        }
    }))
    print(f"[>] bind_success ({client_id})")
    
    await websocket.send(json.dumps({
        "type": "connected",
        "data": {
            "name": "MockRobot",
            "version": "1.0.0",
            "features": ["move", "camera", "gimbal", "dance", "music", "software"],
            "robot_id": "mock-robot-001"
        }
    }))
    print("[>] connected")


async def main():
    print(f"=== Mock Robot (full protocol) ===")
    print(f"Listening ws://0.0.0.0:{PORT}")
    print(f"Methods: display, tts, gimbal, share_code, password")
    print(f"Features: move, camera, gimbal, dance, music, software, wifi, config")
    print(f"{'='*40}")
    server = await websockets.serve(handler, "0.0.0.0", PORT)
    await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped.")
