# agent-swarm

Kernel-level observation and guarding of AI agent swarms running on Kubernetes.

## Language

**Agent**:
A workload that acts autonomously on behalf of a task — running tools, touching files, calling the network.
_Avoid_: bot, worker (when meaning any agent)

**Mock Agent**:
An **Agent** stand-in that, for each **Task** it receives, plays the matching **Scenario** instead of calling an LLM, so it costs no tokens. Occupies exactly the same slot a real **Agent** would.
_Avoid_: fake agent, stub

**Swarm**:
A coordinated group of **Agents**: one **Orchestrator** handing tasks to many **Workers**.

**Orchestrator**:
The **Agent** in a **Swarm** that splits work and hands tasks to **Workers**.

**Worker**:
An **Agent** in a **Swarm** that carries out tasks handed to it by the **Orchestrator**.

**Task**:
A unit of work the **Orchestrator** hands to a **Worker**. A real **Agent** reads it as a prompt; a **Mock Agent** reads it as the name of a **Scenario** to play.
_Avoid_: job, request

**Adapter**:
A thin shim that lets a real **Agent** occupy the **Agent** slot by translating **Tasks** into the Agent's own input and its results back.

**Workspace**:
The one place an **Agent** is allowed to write. Writing anywhere else is misbehaviour.

**Scenario**:
A scripted sequence of actions a **Mock Agent** performs. Either **benign** (ordinary agent work) or **rogue** (misbehaviour such as exfiltration or privilege escalation).

**Guardrail**:
A kernel-level rule that blocks or kills an **Agent** action, as opposed to merely observing it.

## Relationships

- A **Swarm** has exactly one **Orchestrator** and one or more **Workers**
- A **Mock Agent** plays one **Scenario** per **Task**, and may play many over its life
- Mock and real **Agents** receive the same **Tasks**; nothing else about the slot differs
- A **rogue** **Scenario** is expected to trip at least one **Guardrail**
- A **Guardrail** never distinguishes a **Mock Agent** from a real **Agent**

## Flagged ambiguities

- "monitor" was used for both observing and enforcing — resolved: observing is **monitoring**, enforcing is a **Guardrail**.
