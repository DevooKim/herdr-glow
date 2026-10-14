# Herdr Glow

**Herdr 에이전트가 나를 기다릴 때 화면 가장자리가 은은하게 빛나는 앰비언트 라이트.**

[English](README.en.md)

![Herdr 에이전트가 blocked일 때 화면 가장자리에서 주황색 글로우가 숨쉬듯 번지는 모습](assets/herdr-glow-demo.gif)

[Herdr](https://herdr.dev)의 코딩 에이전트가 `blocked`(승인이나 질문 대기) 상태가 되면,
화면 가장자리가 부드럽게 숨쉬듯 빛납니다. 모든 Space, 모니터, 전체화면 앱 위에 표시되고
클릭이나 키보드 포커스는 가로채지 않습니다.

자리를 비웠을 때 놓치지 않게 하면서, 자리에 있을 때는 방해하지 않도록 만들었어요.

1. **짧은 알림.** 에이전트가 blocked가 되면 글로우가 두 번 숨쉬고(약 5.6초) 사라집니다.
2. **자리를 비우면 다시 켜짐.** 여전히 blocked인 상태에서 키보드와 마우스를 30초 동안
   건드리지 않으면 글로우가 다시 켜져서 계속 숨쉽니다.
3. **입력하면 꺼짐.** 키보드나 마우스를 만지면 페이드 아웃합니다. 그 상태로 다시
   자리를 비우면 30초 뒤에 또 켜집니다.
4. **blocked가 풀리면 종료.** blocked인 에이전트가 없어지거나 해당 pane이 닫히면 사라집니다.

blocked가 되는 시점에 이미 자리를 비운 상태라면 짧은 알림 없이 바로 켜집니다.
blocked인 에이전트가 여러 개여도 글로우는 하나만 뜨고, 마지막 하나가 풀릴 때 꺼집니다.

에이전트가 blocked나 done이 되면 화면 아래쪽 가운데에 알약 모양 토스트도 4초간 떠서
어떤 에이전트인지 알려 줍니다(예: `herdr-glow · Claude  is done`).

## 빠른 시작

요구 사항:

- macOS
- 실행 중인 [Herdr](https://herdr.dev) 0.9.0 이상
- Xcode Command Line Tools (`xcode-select --install`). 작은 Swift 헬퍼를 컴파일하는 데 필요합니다.

```sh
herdr plugin install DevooKim/herdr-glow
```

이게 전부예요. 설치하면 헬퍼를 빌드하고 바로 에이전트 상태 변화에 반응합니다.
따로 설정할 액션이나 단축키는 없습니다.

제거하려면:

```sh
herdr plugin uninstall devookim.herdr-glow
```

## 글로우 끄기

done인 pane에 포커스하면 확인한 것으로 보고 글로우를 끕니다. 그래도 남아 있으면
`dismiss` 액션으로 강제로 끌 수 있어요. 상태가 다시 바뀌기 전까지는 켜지지 않습니다.

```sh
herdr plugin action invoke devookim.herdr-glow.dismiss
```

단축키로 쓰려면 Herdr `config.toml`에 추가하세요.

```toml
[[keys.command]]
key = "prefix+g"
type = "plugin_action"
command = "devookim.herdr-glow.dismiss"
description = "dismiss glow"
```

## 동작 방식

플러그인이 Herdr의 `pane.agent_status_changed`, `pane.closed`, `pane.exited` 이벤트를
구독합니다. `bin/on-status-changed.sh`가 blocked/done인 pane을 추적하면서 `bin/glow`를 띄우고
종료하고, 상태가 새로 바뀐 pane이 있으면 `bin/toast`(`src/toast.swift`)를 띄웁니다. 토스트는
`herdr agent get`, `herdr workspace get`으로 에이전트와 워크스페이스 이름을 조회합니다. `bin/glow`는 Swift/AppKit으로 작성한 단일 파일 헬퍼(`src/glow.swift`)입니다.

`glow`는 에이전트가 blocked인 동안에만 실행됩니다. 가장자리에 그라디언트를 그린 투명한
클릭 통과 창을 띄우고, 1초마다 시스템 유휴 시간을 확인하며, 훅이 종료 신호를 보내면
페이드 아웃하고 끝납니다. 별도 권한은 필요 없고, 실행 중 메모리는 약 40MB, CPU는
측정되지 않을 만큼 적게 씁니다.

## 설정 바꾸기

플러그인 디렉토리의 `bin/on-status-changed.sh`에서 `glow` 호출 줄을 수정하세요.
위치는 `herdr plugin list`로 확인할 수 있습니다. 색은 스크립트 상단의 `BLOCKED_COLOR`(기본 `FF8A1F`), `DONE_COLOR`(기본 `34C759`)로 바꿉니다.

```sh
"$DIR/glow" --color "$WANT" --width 60 --watch --idle 30 --intro 5.6
```

| 옵션 | 기본값 | 설명 |
| --- | --- | --- |
| `--color RRGGBB` | `FF8A1F` | 글로우 색 |
| `--width PT` | `140` (훅에서는 `60`) | 글로우 두께(pt) |
| `--watch` | 꺼짐 | 짧게 알린 뒤 자리를 비우면 다시 켬 |
| `--idle SEC` | `30` | 다시 켜기까지의 유휴 시간 |
| `--intro SEC` | `5.6` | 짧은 알림 길이 |
| `--duration SEC` | `3` | `--watch` 없이 한 번만 보여 줄 시간. `0`이면 끌 때까지 유지 |

직접 실행해 볼 수도 있어요. `Ctrl+C`나 `pkill glow`로 끕니다.

```sh
bin/glow --duration 0 --width 60
```

`src/glow.swift`를 수정했다면 다음 명령으로 다시 빌드하세요.

```sh
swiftc -O src/glow.swift -o bin/glow
```

## 제한 사항

- macOS 전용입니다. 오버레이에 AppKit을 사용합니다.
- 글로우는 실행 시점에 연결된 디스플레이에만 표시됩니다.
- `blocked`(주황)와 `done`(초록) 상태를 감지합니다. 둘이 동시에 있으면 blocked가 우선합니다. `idle`에는 반응하지 않습니다.

## 라이선스

MIT
