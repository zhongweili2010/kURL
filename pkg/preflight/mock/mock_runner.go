// Code generated by MockGen. DO NOT EDIT.
// Source: pkg/preflight/runner.go

// Package mock_preflight is a generated GoMock package.
package mock_preflight

import (
	context "context"
	reflect "reflect"

	gomock "github.com/golang/mock/gomock"
	analyzer "github.com/replicatedhq/troubleshoot/pkg/analyze"
	v1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
)

// MockRunner is a mock of Runner interface.
type MockRunner struct {
	ctrl     *gomock.Controller
	recorder *MockRunnerMockRecorder
}

// MockRunnerMockRecorder is the mock recorder for MockRunner.
type MockRunnerMockRecorder struct {
	mock *MockRunner
}

// NewMockRunner creates a new mock instance.
func NewMockRunner(ctrl *gomock.Controller) *MockRunner {
	mock := &MockRunner{ctrl: ctrl}
	mock.recorder = &MockRunnerMockRecorder{mock}
	return mock
}

// EXPECT returns an object that allows the caller to indicate expected use.
func (m *MockRunner) EXPECT() *MockRunnerMockRecorder {
	return m.recorder
}

// Run mocks base method.
func (m *MockRunner) Run(ctx context.Context, spec *v1beta2.HostPreflight, progressChan chan interface{}) ([]*analyzer.AnalyzeResult, error) {
	m.ctrl.T.Helper()
	ret := m.ctrl.Call(m, "Run", ctx, spec, progressChan)
	ret0, _ := ret[0].([]*analyzer.AnalyzeResult)
	ret1, _ := ret[1].(error)
	return ret0, ret1
}

// Run indicates an expected call of Run.
func (mr *MockRunnerMockRecorder) Run(ctx, spec, progressChan interface{}) *gomock.Call {
	mr.mock.ctrl.T.Helper()
	return mr.mock.ctrl.RecordCallWithMethodType(mr.mock, "Run", reflect.TypeOf((*MockRunner)(nil).Run), ctx, spec, progressChan)
}