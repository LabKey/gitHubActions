FROM tchadick/base_action

LABEL \
  "name"="LabKey Release Merging Action" \
  "repository"="https://github.com/LabKey/gitHubActions.git" \
  "maintainer"="Trey Chadick"

ADD *.sh /
RUN chmod +x *.sh 

ENTRYPOINT ["/entrypoint.sh"]