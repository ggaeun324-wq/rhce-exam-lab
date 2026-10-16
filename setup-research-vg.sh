#!/bin/bash
# Q9(LVM) 용: 컨테이너에 실제 디스크가 없으므로 루프백 기반 VG 'research'(~1GiB)를 만든다.
# 1500MiB 요청은 실패(공간 부족)하고 800MiB 는 성공 → 덤프 Q9 시나리오 재현.
#
# 중요(WSL2 공유커널 문제 해결):
#  - 5개 노드는 커널 device-mapper/loop 를 공유한다. 과거에는 모든 노드가 동일한
#    /var/lib/research-disk.img 를 backing 으로 써서 loop 장치가 서로 충돌하고 LVM
#    메타데이터가 손상됐다. 손상된 loop 를 vgs 가 스캔하면 "Retrying metadata scan."
#    이 STDOUT 으로 새어나오고, 이때 ansible 의 LVM fact 파서가 IndexError 로 죽어
#    ansible_memtotal_mb / ansible_bios_version / ansible_devices 등 하드웨어 fact 가
#    통째로 사라진다(→ Q13 hwreport MEMORY 라인 실패).
#  - 해결: 노드마다 고유 backing 경로(/var/lib/research-<hostname>.img)를 쓰고,
#    LVM devices 파일을 자기 PV 만 담도록 재생성한다. 그러면 vgs 가 다른 노드의
#    loop 를 스캔하지 않아 출력이 깨끗해지고 fact 수집이 정상 동작한다.
set +e

H=$(hostname -s)
IMG=/var/lib/research-$H.img
OLDIMG=/var/lib/research-disk.img

rm -f /etc/lvm/cache/.cache 2>/dev/null || true

# 이미 깨끗한 research VG(자기 PV 기반)가 있고 vgs 출력에 잡음이 없으면 그대로 둔다.
if vgs research >/dev/null 2>&1; then
    NOISE=$(vgs --noheadings 2>/dev/null | grep -c "Retrying metadata scan")
    if [ "${NOISE:-0}" = "0" ]; then
        vgs research
        exit 0
    fi
fi

# --- 재구축 (손상/미존재/잡음 시) ---
vgchange -an research 2>/dev/null
vgremove -ff -y research 2>/dev/null
dmsetup remove research-data 2>/dev/null
rm -rf /dev/research 2>/dev/null

# 자기(옛/새) 경로에 붙은 loop 만 정리
for L in $(losetup -j "$OLDIMG" 2>/dev/null | cut -d: -f1) \
         $(losetup -j "$IMG"    2>/dev/null | cut -d: -f1); do
    losetup -d "$L" 2>/dev/null
done
rm -f "$OLDIMG" 2>/dev/null

# 자기 PV 만 담도록 devices 파일 재생성
rm -f /etc/lvm/devices/system.devices 2>/dev/null

[ -f "$IMG" ] || dd if=/dev/zero of="$IMG" bs=1M count=1024 status=none
LOOP=$(losetup -f --show "$IMG") || exit 0
wipefs -a "$LOOP" >/dev/null 2>&1
pvcreate -ff -y "$LOOP" >/dev/null 2>&1
vgcreate research "$LOOP" >/dev/null 2>&1
# devices 파일에 자기 PV 확실히 등록
lvmdevices --adddev "$LOOP" >/dev/null 2>&1
vgimportdevices research >/dev/null 2>&1
vgs research || true
