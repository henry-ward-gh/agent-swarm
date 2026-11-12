FROM alpine:3.24.4

RUN apk add --no-cache bash coreutils curl jq tar valkey-cli \
 && adduser -D -H -u 10001 agent

ARG AGENT_VERSION=dev
ENV AGENT_HOME=/opt/agent \
    AGENT_VERSION=${AGENT_VERSION} \
    PATH=/opt/agent/bin:$PATH

COPY --chmod=0755 bin/ /opt/agent/bin/
COPY --chmod=0755 scenarios/ /opt/agent/scenarios/
COPY --chmod=0755 goals/ /opt/agent/goals/

USER 10001
WORKDIR /workspace
ENTRYPOINT ["agent"]
CMD ["run"]
