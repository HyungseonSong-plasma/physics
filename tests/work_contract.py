# FileRank: C
"""Installed framework pilot using elementary analytical physics fixtures."""

from pathlib import Path
import sys
import unittest

import work
from work.libs.frame import FrameContract
from work.libs.command import Command, CommandRegistry, local_plan
from work.libs.testing import TestSuite, SuiteRegistry


class KineticEnergy(Command):
    help = "Analytic kinetic energy fixture"
    plan = local_plan(lambda ctx, args: 0.5 * 2.0 * 3.0**2)


class PhysicsContract(TestSuite):
    def test_force(self):
        def check(ctx):
            frame = FrameContract(("prepare", "action")).bind(
                prepare=lambda acceleration: 2.0 * acceleration,
                action=lambda force: force)
            self.assertEqual(frame.execute(3.0), 6.0)
        self.run_contract(check=check)

    def test_kinetic_energy(self):
        def check(ctx):
            registry = CommandRegistry()
            registry.register("kinetic-energy")(KineticEnergy)
            self.assertEqual(registry.configured(("kinetic-energy",))["kinetic-energy"].execute(None), 9.0)
        self.run_contract(check=check)


if __name__ == "__main__":
    assert Path(work.__file__).resolve().is_relative_to(Path(sys.prefix).resolve())
    registry = SuiteRegistry()
    registry.register("physics")(PhysicsContract)
    result = unittest.TextTestRunner(verbosity=2).run(registry.build(("physics",)))
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 2 else 1)
