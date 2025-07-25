/*
 * Copyright 2022-2025 Hewlett Packard Enterprise Development LP
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package test

import (
	"context"
	"flag"
	"fmt"
	"os"
	"testing"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	. "github.com/NearNodeFlash/nnf-integration-test/internal"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	zapcr "sigs.k8s.io/controller-runtime/pkg/log/zap"

	"k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	log "sigs.k8s.io/controller-runtime/pkg/log"

	dwsv1alpha4 "github.com/DataWorkflowServices/dws/api/v1alpha4"
	lusv1alpha1 "github.com/NearNodeFlash/lustre-fs-operator/api/v1alpha1"
	nnfv1alpha8 "github.com/NearNodeFlash/nnf-sos/api/v1alpha8"
)

var (
	ignoreReservation bool

	ctx    context.Context
	cancel context.CancelFunc

	testEnv *envtest.Environment

	k8sClient client.Client
)

func init() {
	flag.BoolVar(&ignoreReservation, "ignore-reservation", false, "Ignore any reservations on the system that might prevent test execution")
}

func TestEverything(t *testing.T) {
	RegisterFailHandler(FailHandler)
	RunSpecs(t, "Integration Test Suite")
}

var _ = BeforeSuite(func() {

	encoder := zapcore.NewConsoleEncoder(zap.NewDevelopmentEncoderConfig())
	zaplogger := zapcr.New(zapcr.WriteTo(GinkgoWriter), zapcr.Encoder(encoder), zapcr.UseDevMode(true))
	log.SetLogger(zaplogger)

	ctx, cancel = context.WithCancel(context.Background())

	By("Retrieving Workflow State Timeouts")
	// given a default timeout and a env var name, get the duration string and parse it
	getTimeoutDuration := func(d, env string) time.Duration {
		s := d
		// if set, use the env variable
		if e := os.Getenv(env); e != "" {
			s = e
		}
		// parse it
		t, err := time.ParseDuration(s)
		if err != nil {
			panic(fmt.Sprintf("cannot prase timeout: %v", err))
		}
		return t
	}

	lowTimeoutDuration := getTimeoutDuration(lowTimeout, "LTIMEOUT")
	highTimeoutDuration := getTimeoutDuration(highTimeout, "HTIMEOUT")
	ctx = context.WithValue(ctx, "lowTimeout", lowTimeoutDuration)
	ctx = context.WithValue(ctx, "highTimeout", highTimeoutDuration)
	ctx = context.WithValue(ctx, "highTimeoutStates", highTimeoutStates)
	fmt.Printf("Using a low timeout of '%s'\n", lowTimeoutDuration)
	fmt.Printf("Using a high timeout of '%s' for the following states: %v\n", highTimeoutDuration, highTimeoutStates)

	By("Bootstrapping Test Env")
	useExistingClustre := true
	testEnv = &envtest.Environment{UseExistingCluster: &useExistingClustre}

	cfg, err := testEnv.Start()
	Expect(err).NotTo(HaveOccurred())
	Expect(cfg).NotTo(BeNil())

	By("Adding Schemes")
	err = dwsv1alpha4.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())

	err = lusv1alpha1.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())

	err = nnfv1alpha8.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())

	By("Creating Client")
	k8sClient, err = client.New(cfg, client.Options{Scheme: scheme.Scheme})
	Expect(err).NotTo(HaveOccurred())
	Expect(k8sClient).NotTo(BeNil())

	// Check if the system is currently in need of tirage and prevent test execution if so
	if IsSystemInNeedOfTriage(ctx, k8sClient) {
		AbortSuite(fmt.Sprintf("System requires triage. Delete the '%s' namespace when finished", TriageNamespaceName))
	}

	// Check if the system is being reserved by a developer
	if !ignoreReservation {
		By("Checking for system reservation")
		reserved, developer, err := IsSystemReserved(ctx, k8sClient)
		Expect(err).NotTo(HaveOccurred())

		if reserved {
			AbortSuite(fmt.Sprintf("System is current reserved by '%s'", developer))
		}
	}

})

var _ = AfterSuite(func() {
	cancel()
	err := testEnv.Stop()
	Expect(err).NotTo(HaveOccurred())
})

func FailHandler(message string, callerSkip ...int) {
	if ctx != nil && k8sClient != nil {
		if err := SetSystemInNeedOfTriage(ctx, k8sClient); err != nil {
			log.Log.Error(err, "Failed to configure the system for triage")
		}
	}

	Fail(message, callerSkip...)
}
