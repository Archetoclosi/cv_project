import unittest
import os
import tempfile
from unittest.mock import patch, MagicMock
import sys

# Add tools directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tools'))


class TestProcessManager(unittest.TestCase):
    def test_process_config_creation(self):
        """Test ProcessConfig can be created with required fields"""
        from orchestrator import ProcessConfig

        config = ProcessConfig(
            name="test_process",
            script="tools/test.py",
            args=["arg1", "arg2"],
            console=True,
            restart=True
        )
        assert config.name == "test_process"
        assert config.script == "tools/test.py"
        assert config.args == ["arg1", "arg2"]
        assert config.console is True
        assert config.restart is True

    def test_process_manager_initialization(self):
        """Test ProcessManager initializes with empty process list"""
        from orchestrator import ProcessManager

        manager = ProcessManager(verbose=False, log_output=False)
        assert manager.processes == {}
        assert manager.verbose is False
        assert manager.log_output is False

    def test_cli_argument_parsing(self):
        """Test that CLI arguments are parsed correctly"""
        from orchestrator import parse_arguments

        args = parse_arguments(["--verbose"])
        assert args.verbose is True
        assert args.log is False

        args = parse_arguments(["--log"])
        assert args.verbose is False
        assert args.log is True

        args = parse_arguments([])
        assert args.verbose is False
        assert args.log is False


if __name__ == "__main__":
    unittest.main()
