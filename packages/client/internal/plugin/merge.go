package plugin

import (
	"fmt"
	"maps"
)

// Merger handles merging of JSON objects.
type Merger struct{}

// NewMerger creates a new Merger instance.
func NewMerger() *Merger {
	return &Merger{}
}

// Merge combines two JSON objects.
// If keys collide, 'overlay' overwrites 'base'.
// If both values are maps, they are merged recursively.
func (m *Merger) Merge(base, overlay map[string]any) (map[string]any, error) {
	if base == nil {
		return overlay, nil
	}
	if overlay == nil {
		return base, nil
	}

	result := make(map[string]any)

	// Copy base
	maps.Copy(result, base)

	// Merge overlay
	for k, v := range overlay {
		if existing, ok := result[k]; ok {
			// If both are maps, recurse
			existingMap, ok1 := existing.(map[string]any)
			newMap, ok2 := v.(map[string]any)

			if ok1 && ok2 {
				merged, err := m.Merge(existingMap, newMap)
				if err != nil {
					return nil, fmt.Errorf("failed to merge key %s: %w", k, err)
				}
				result[k] = merged
			} else {
				// Otherwise overwrite
				result[k] = v
			}
		} else {
			// New key
			result[k] = v
		}
	}

	return result, nil
}
