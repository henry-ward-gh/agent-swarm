# Scenarios arrive as Tasks, not as pod configuration

A Mock Agent does not get its Scenario from pod config (e.g. `SCENARIO=exfil`). Instead the Orchestrator sends it a Task, and the Mock Agent plays the Scenario named by that Task; a real Agent receives the very same Task as a prompt. We chose this so the Agent slot is genuinely swappable — mock and real Agents get identical pods and identical input, and the only thing that changes is the image — and so a rogue run is simply a rogue Task sent to an ordinary Worker, exactly how a real swarm would be compromised.

## Consequences

- Worker pods are long-running and play many Scenarios over their life. Each Scenario runs as a child process of the Worker, as a real Agent's tool call would, so a Guardrail `Sigkill` kills that process (exit 137) and the Worker survives to report the Task `failed` with the exit code. (Amended: originally said a `Sigkill` would restart the container.)
- Tests drive behaviour by submitting Goals to the Orchestrator, not by redeploying pods.
- (Amended: the *pod* is identical, but the Task's payload is not. A Task names a `scenario` for a Mock Agent or carries a `prompt` for a real one, and the Mock Orchestrator only sends `scenario` Tasks. So real Workers need an Orchestrator that sends prompts. See [Swapping in a real Agent](../real-agents.md).)
