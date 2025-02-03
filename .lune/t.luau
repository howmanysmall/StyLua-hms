local RegEx = require("@lune/regex")
local process = require("@lune/process")

local EXPRESSIONS_STRING = "const MAX_EXPRESSIONS: usize = %*;"
local EXPRESSIONS_PATTERN = RegEx.new(string.format(EXPRESSIONS_STRING, "(\\d|usize::MAX)"))

local assignmentFileSource = [[

/// Determines whether we should prevent hanging at the equals token depending on the RHS expression
fn prevent_equals_hanging(expression: &Expression) -> bool {
    match expression {
        Expression::Function(_) => true,
        Expression::FunctionCall(function_call) => is_complex_function_call(function_call),
        #[cfg(feature = "luau")]
        Expression::IfExpression(_) => true,
        #[cfg(feature = "luau")]
        Expression::TypeAssertion { expression, .. } => prevent_equals_hanging(expression),
        _ => false,
    }
}

const MAX_EXPRESSIONS: usize = 1;

/// Attempts different formatting tactics on an expression list being assigned (`= foo, bar`), to find the best
/// formatting output.
fn attempt_assignment_tactics(
]]

if not EXPRESSIONS_PATTERN:isMatch(assignmentFileSource) then
	warn("Max expressions not found")
	process.exit(1)
end

local expressionsCapture = EXPRESSIONS_PATTERN:captures(assignmentFileSource)
if not expressionsCapture then
	warn("Failed to capture max expressions?")
	process.exit(1)
	return "stylua2", "hms", "", ""
end
local expressionsCaptureMatch = expressionsCapture:get(1)
if not expressionsCaptureMatch then
	warn("Failed to capture max expressions type?")
	process.exit(1)
	return "stylua2", "hms", "", ""
end

print(expressionsCaptureMatch.text)
