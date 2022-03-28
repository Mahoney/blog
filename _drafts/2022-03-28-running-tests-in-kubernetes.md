---
layout: post
title: Running Tests in Kubernetes
date: '2022-03-28T15:53:34.000+0100'
author: Robert Elliot
tags:
---

Recently I have had cause to run tests in Kubernetes via a GitHub Action, and 
it's a *huge* pain so capturing it here.

I've shown it as a `gradle test` run but it should be more widely applicable.

Nice thing about is is that by mounting the local directory the whole way
through when the files are generated they are generated where you would expect
to see them locally.

## Basics:
1. GitHub Action steps
   ```yaml
      - name: start minikube
        uses: medyagh/setup-minikube@latest

      - name: K8S Tests
          run: run-k8s-tests.sh
   ```
2. run-k8s-tests.sh
   ```bash
   #!/usr/bin/env bash

   set -exuo pipefail
   
   main() {
     trap 'cleanup' EXIT

     kubectl config use-context minikube
   
     ensure_a_clean_namespace

     prepare_minikube

     kubectl apply \
       -f other-resources.yml \
       -f k8s-tests.yml

     wait_for_tests_to_finish
   }

   ensure_a_clean_namespace() {
     kubectl delete all --all -n k8s-test
   }
   
   prepare_minikube() {
     minikube mount .:/home/gradle/project &
   }

   wait_for_tests_to_finish() {
     # Wait for the job to start - otherwise there will be no pods
     kubectl wait --for=jsonpath='{.status.active}'=1 job/k8s-tests --timeout=30s -n k8s-test
   
     # Wait for the pods to be ready - be aware if the jobs is really fast this
     # will fail because ready will go from true to false too fast for the check
     # I cannot find a truly reliable of checking whether the pods *have* started in the past
     kubectl wait --for=condition=ready pods --selector=job-name=k8s-tests --timeout=30s -n k8s-test

     # Follow the logs to get real time info on what is happening
     kubectl logs job/k8s-tests --follow -n k8s-test

     # The pods should be back with ready=false when they exit
     kubectl wait --for=condition=ready=false pods --selector=job-name=k8s-tests --timeout=30s -n k8s-test
     # Meaning this should work
     local exit_code; exit_code=$(kubectl get pods --selector=job-name=k8s-tests --output=jsonpath='{.items[0].status.containerStatuses[0].state.terminated.exitCode}' -n k8s-test)
     return "$exit_code"
   }
   
   cleanup() {
     local running_jobs; running_jobs=$(jobs -p)
     # shellcheck disable=SC2086
     kill $running_jobs || true
     # shellcheck disable=SC2086
     wait
   }

   main "$@"
   ```
3. k8s-tests.yml
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: k8s-tests
   spec:
     parallelism: 1
     completions: 1
     backoffLimit: 0
     # Set this to something appropriate!
     activeDeadlineSeconds: 600
     template:
       spec:
         containers:
           - name: k8s-tests
             image: gradle:7.4.0-jdk17
             command: ["gradle", "test"]
             volumeMounts:
               - mountPath: /home/gradle/project
                 name: gradle-project
         restartPolicy: Never
         volumes:
           - name: gradle-project
             hostPath:
               path: /home/gradle/project
   ```

Nice feature - `run-k8s-tests.sh` will run quite happily locally if you have
minikube & bash installed.

The meat of the complication is the `wait_for_tests_to_finish` bash function.

If you are testing an image you are building, you can build and run it the tests
fairly efficiently in minikube as so:
```bash
#!/bin/bash
set -euo pipefail

eval "$(minikube docker-env)"

docker buildx build . \
  -t myimage:local

./run-k8s-tests.sh
```

(I'm using buildx build here, but if you don't need buildx a docker build will
do.)
