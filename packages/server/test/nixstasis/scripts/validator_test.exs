defmodule Nixstasis.Scripts.ValidatorTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Scripts.Validator

  test "renders canonical stary content" do
    rendered =
      Validator.render_stary(%{"name" => "demo", "schema" => %{"type" => "object"}, "version" => "1"}, "def main():\n  return {}\n")

    assert rendered =~ "---\n"
    assert rendered =~ "name: \"demo\""
    assert rendered =~ "schema: %{"
    assert rendered =~ "def main():"
  end

  test "validates a representative stary document" do
    content = """
    ---
    name: demo
    version: "1"
    schema:
      type: object
      properties:
        value:
          type: string
    ---

    def main():
        return {"value": "ok"}
    """

    assert {:ok, %{front_matter: fm, body: body, rendered_content: rendered}} = Validator.validate_content(content)
    assert fm["name"] == "demo"
    assert body =~ "def main()"
    assert rendered =~ "name: \"demo\""
  end

  test "rejects missing body" do
    content = """
    ---
    name: demo
    schema:
      type: object
    ---
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "script body"
  end

  test "rejects invalid front matter" do
    content = """
    ---
    name: ""
    schema:
      type: object
    ---

    def main():
        return {}
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "name"
  end
end
