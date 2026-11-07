# SPDX-License-Identifier: MIT
"""Resize-metric planning for the Apple installer engine.

The planner that raises ``inconsistent macOS resize metrics`` ships in the
macOS installer engine (``omarchy_planner.py``). These tests drive that
function with the layout from omacom/omarchy#17820. They do not call diskutil
and they do not install on hardware.
"""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace


class FakeOSInstaller:
    def __init__(self, dutil, data, template):
        self.min_recommended_size = template["minimum_size"]
        self.min_size = template.get("floor_size", template["minimum_size"])


sys.modules["osinstall"] = SimpleNamespace(OSInstaller=FakeOSInstaller)
sys.modules["util"] = SimpleNamespace(
    align_down=lambda value, alignment: value // alignment * alignment,
)
sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[4] / "apple-installer/Engine/overlay/src"),
)

from omarchy_planner import PlanningError, collect_inventory  # noqa: E402


ALIGN = 1024**2
PARTITION = 245_107_195_904
CEILING = 168_108_163_072
FREE = 50_000_000_000
DISK = 256_000_000_000
TRAPPED = PARTITION - CEILING


class Installer:
    def __init__(self, part_size, disk, bounds, refresh=None, info=None):
        self.part = SimpleNamespace(
            name="disk0s2",
            offset=4096,
            size=part_size,
            container={"CapacityCeiling": part_size},
        )
        self.sys_disk = "disk0"
        self.bounds = bounds
        self.calls = 0
        self.data = {
            "os_list": [
                {
                    "omarchy_target": "apple-silicon-full-os",
                    "minimum_size": 64 * 1024**3,
                    "floor_size": 30 * 1024**3,
                }
            ]
        }
        fields = {"get_disk_size": lambda _name: disk}
        if refresh is not None:
            fields["refresh_part"] = refresh
        if info is not None:
            fields["get_partition_info"] = info
        self.dutil = SimpleNamespace(**fields)

    def get_resize_bounds(self, part):
        self.calls += 1
        if callable(self.bounds):
            return self.bounds(self.calls, part)
        return dict(self.bounds)


def inventory(installer):
    return collect_inventory(installer, [], [installer.part], 2 * 1024**3, ALIGN)


class ResizeMetricTests(unittest.TestCase):
    def test_matching_metrics_are_not_re_queried(self):
        total = 200 * 1024**3
        free = 100 * 1024**3
        refreshed = []
        installer = Installer(
            total,
            256 * 1024**3,
            {
                "total_bytes": total,
                "free_bytes": free,
                "diskutil_minimum_bytes": total - free + 1024**3,
            },
            refresh=lambda part: refreshed.append(part.name),
        )

        (candidate,) = inventory(installer)["candidates"]

        self.assertEqual(refreshed, [])
        self.assertEqual(installer.calls, 1)
        self.assertEqual(candidate["length_bytes"], total)
        used = total - free
        value = used + 38_000_000_000
        aligned = (value + ALIGN - 1) // ALIGN * ALIGN
        self.assertEqual(candidate["minimum_container_bytes"], aligned)

    def test_invalid_metrics_fail_closed(self):
        for disk in (None, True, -1, 2**64, "256000000000"):
            with self.subTest(disk=disk):
                installer = Installer(
                    PARTITION,
                    disk,
                    {
                        "total_bytes": PARTITION,
                        "free_bytes": FREE,
                        "diskutil_minimum_bytes": CEILING,
                    },
                )
                with self.assertRaisesRegex(PlanningError, "invalid macOS resize metrics"):
                    inventory(installer)

    def test_re_query_keeps_a_settled_sample(self):
        def bounds(call, part):
            if call == 1:
                return {
                    "total_bytes": CEILING,
                    "free_bytes": FREE,
                    "diskutil_minimum_bytes": CEILING,
                }
            return {
                "total_bytes": part.size,
                "free_bytes": FREE - ALIGN,
                "diskutil_minimum_bytes": part.size - 1024**3,
            }

        def info(name, refresh_apfs=False):
            self.assertEqual(name, "disk0s2")
            self.assertTrue(refresh_apfs)
            return SimpleNamespace(size=CEILING, container={"CapacityCeiling": CEILING})

        refreshed = []
        installer = Installer(
            PARTITION,
            DISK,
            bounds,
            refresh=lambda part: refreshed.append(part.name),
            info=info,
        )

        (candidate,) = inventory(installer)["candidates"]

        self.assertEqual(refreshed, ["disk0s2"])
        self.assertEqual(installer.calls, 2)
        self.assertEqual(installer.part.size, CEILING)
        self.assertEqual(candidate["length_bytes"], CEILING)

    def test_stable_gap_uses_the_container_ceiling(self):
        # Reported M1 256GB store: disk0s2 stayed 245,107,195,904 bytes while
        # the APFS ceiling fell to 168,108,163,072 (76,999,032,832 unaccounted).
        self.assertEqual(TRAPPED, 76_999_032_832)
        installer = Installer(
            PARTITION,
            DISK,
            {
                "total_bytes": CEILING,
                "free_bytes": FREE,
                "diskutil_minimum_bytes": CEILING,
            },
        )

        (candidate,) = inventory(installer)["candidates"]

        self.assertEqual(installer.calls, 2)
        self.assertEqual(candidate["length_bytes"], PARTITION)
        self.assertEqual(candidate["minimum_container_bytes"], CEILING)
        self.assertEqual(PARTITION - candidate["minimum_container_bytes"], TRAPPED)

    def test_reserve_is_taken_from_the_ceiling(self):
        used = CEILING - FREE
        value = used + 38_000_000_000
        aligned = (value + ALIGN - 1) // ALIGN * ALIGN
        installer = Installer(
            PARTITION,
            DISK,
            {
                "total_bytes": CEILING,
                "free_bytes": FREE,
                "diskutil_minimum_bytes": used + 1_000_000_000,
            },
        )

        (candidate,) = inventory(installer)["candidates"]

        self.assertEqual(aligned, 156_108_849_152)
        self.assertEqual(candidate["minimum_container_bytes"], aligned)
        self.assertLess(aligned, CEILING)
        self.assertEqual(candidate["length_bytes"], PARTITION)

    def test_ceiling_above_the_partition_fails_closed(self):
        installer = Installer(
            200_000_000_000,
            DISK,
            {
                "total_bytes": 210_000_000_000,
                "free_bytes": 40_000_000_000,
                "diskutil_minimum_bytes": 180_000_000_000,
            },
        )
        with self.assertRaisesRegex(PlanningError, "inconsistent macOS resize metrics"):
            inventory(installer)

    def test_failed_re_query_still_plans_the_smaller_container(self):
        def refresh(part):
            raise OSError("diskutil info failed")

        installer = Installer(
            PARTITION,
            DISK,
            {
                "total_bytes": CEILING,
                "free_bytes": FREE,
                "diskutil_minimum_bytes": CEILING,
            },
            refresh=refresh,
        )

        (candidate,) = inventory(installer)["candidates"]

        self.assertEqual(installer.part.size, PARTITION)
        self.assertEqual(candidate["length_bytes"], PARTITION)
        self.assertEqual(candidate["minimum_container_bytes"], CEILING)


if __name__ == "__main__":
    unittest.main()
