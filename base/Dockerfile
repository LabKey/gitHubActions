FROM alpine/git

LABEL \
  "name"="LabKey Hub Container" \
  "repository"="https://github.com/LabKey/gitHubActions.git" \
  "maintainer"="Trey Chadick"

RUN apk add --update --no-cache curl bash libc6-compat tar

WORKDIR /

# Install hub
RUN curl -fsSL https://github.com/github/hub/raw/master/script/get | bash -s 2.14.1

CMD /bin/bash
