# Scenarios arrive as Tasks, not as pod configuration

A Mock Agent does not get its Scenario from pod config (e.g. `SCENARIO=exfil`). Instead the Orchestrator sends it a Task, and the Mock Agent plays the Scenario named by that Task; a real Agent receives the very same Task as a prompt. We chose this so the Agent slot is genuinely swappable — mock and real Agents get identical pods and identical input, and the only thing that changes is the image — and so a rogue run is simply a rogue Task sent to an ordinary Worker, exactly how a real swarm would be compromised.

## Consequences

- Worker pods are long-running and play many Scenarios over their life; a Guardrail `Sigkill` shows up as a container restart (exit 137), not a failed Job.
- Tests drive behaviour through the Orchestrator's Task protocol, not by redeploying pods.
