# agent-swarm

Kernel-level observation and guarding of AI agent swarms running on Kubernetes.

## Language

**Agent**:
A workload that acts autonomously on behalf of a task — running tools, touching files, calling the network.
_Avoid_: bot, worker (when meaning any agent)

**Mock Agent**:
An **Agent** stand-in that plays a **Scenario** instead of calling an LLM, so it costs no tokens. Occupies exactly the same slot a real **Agent** would.
_Avoid_: fake agent, stub

**Swarm**:
A coordinated group of **Agents**: one **Orchestrator** handing tasks to many **Workers**.

**Orchestrator**:
The **Agent** in a **Swarm** that splits work and hands tasks to **Workers**.

**Worker**:
An **Agent** in a **Swarm** that carries out tasks handed to it by the **Orchestrator**.

**Scenario**:
A scripted sequence of actions a **Mock Agent** performs. Either **benign** (ordinary agent work) or **rogue** (misbehaviour such as exfiltration or privilege escalation).

**Guardrail**:
A kernel-level rule that blocks or kills an **Agent** action, as opposed to merely observing it.

## Relationships

- A **Swarm** has exactly one **Orchestrator** and one or more **Workers**
- A **Mock Agent** plays exactly one **Scenario**
- A **rogue** **Scenario** is expected to trip at least one **Guardrail**

## Flagged ambiguities

- "monitor" was used for both observing and enforcing — resolved: observing is **monitoring**, enforcing is a **Guardrail**.
