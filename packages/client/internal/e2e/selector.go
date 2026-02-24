package e2e

import "fmt"

// SelectJourneys returns the selected journeys or the full list if none selected.
func SelectJourneys(all, selected []string) ([]string, error) {
	if len(selected) == 0 {
		return all, nil
	}

	lookup := make(map[string]struct{}, len(all))
	for _, journey := range all {
		lookup[journey] = struct{}{}
	}

	for _, journey := range selected {
		if _, ok := lookup[journey]; !ok {
			return nil, fmt.Errorf("unknown journey: %s", journey)
		}
	}

	return selected, nil
}
