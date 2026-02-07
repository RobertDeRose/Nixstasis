package plugin

import (
	"reflect"
	"testing"
)

func TestMerge(t *testing.T) {
	tests := []struct {
		name     string
		base     map[string]any
		input    map[string]any
		expected map[string]any
		wantErr  bool
	}{
		{
			name: "Basic Merge",
			base: map[string]any{
				"device": map[string]any{"uptime": 100},
			},
			input: map[string]any{
				"cpu": map[string]any{"usage": 50},
			},
			expected: map[string]any{
				"device": map[string]any{"uptime": 100},
				"cpu":    map[string]any{"usage": 50},
			},
			wantErr: false,
		},
		{
			name: "Collision Overwrite",
			base: map[string]any{
				"temp": 20,
			},
			input: map[string]any{
				"temp": 30,
			},
			expected: map[string]any{
				"temp": 30,
			},
			wantErr: false,
		},
		{
			name: "Nested Merge",
			base: map[string]any{
				"stats": map[string]any{"a": 1},
			},
			input: map[string]any{
				"stats": map[string]any{"b": 2},
			},
			expected: map[string]any{
				"stats": map[string]any{"a": 1, "b": 2},
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			merger := NewMerger()
			got, err := merger.Merge(tt.base, tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("Merger.Merge() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.expected) {
				t.Errorf("Merger.Merge() = %v, want %v", got, tt.expected)
			}
		})
	}
}
