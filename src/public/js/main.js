document.addEventListener('DOMContentLoaded', function() {
    const form = document.getElementById('registrationForm');
    const submitBtn = document.getElementById('submitBtn');
    
    const fields = {
        name: document.getElementById('name'),
        squadron: document.getElementById('squadron'),
        email: document.getElementById('email'),
        terms: document.getElementById('terms')
    };
    
    const errors = {
        name: document.getElementById('name-error'),
        squadron: document.getElementById('squadron-error'),
        email: document.getElementById('email-error')
    };

    function validateField(field, value) {
        switch(field) {
            case 'name':
                if (!value || value.length < 2) {
                    return 'Name must be at least 2 characters long';
                }
                if (value.length > 255) {
                    return 'Name must be less than 255 characters';
                }
                return '';
                
            case 'squadron':
                if (!value || value.trim().length === 0) {
                    return 'Squadron is required';
                }
                if (value.length > 100) {
                    return 'Squadron must be less than 100 characters';
                }
                return '';
                
            case 'email':
                const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                if (!value || !emailRegex.test(value)) {
                    return 'Please enter a valid email address';
                }
                return '';
                
            default:
                return '';
        }
    }

    function showError(field, message) {
        if (errors[field]) {
            errors[field].textContent = message;
            fields[field].classList.add('error');
        }
    }

    function clearError(field) {
        if (errors[field]) {
            errors[field].textContent = '';
            fields[field].classList.remove('error');
        }
    }

    Object.keys(fields).forEach(fieldName => {
        if (fieldName !== 'terms' && fields[fieldName]) {
            fields[fieldName].addEventListener('blur', function() {
                const error = validateField(fieldName, this.value);
                if (error) {
                    showError(fieldName, error);
                } else {
                    clearError(fieldName);
                }
            });

            fields[fieldName].addEventListener('input', function() {
                if (this.classList.contains('error')) {
                    const error = validateField(fieldName, this.value);
                    if (!error) {
                        clearError(fieldName);
                    }
                }
            });
        }
    });

    form.addEventListener('submit', async function(e) {
        e.preventDefault();
        
        let hasErrors = false;
        
        Object.keys(fields).forEach(fieldName => {
            if (fieldName !== 'terms') {
                const error = validateField(fieldName, fields[fieldName].value);
                if (error) {
                    showError(fieldName, error);
                    hasErrors = true;
                } else {
                    clearError(fieldName);
                }
            }
        });
        
        if (!fields.terms.checked) {
            alert('You must agree to the terms of service');
            hasErrors = true;
        }
        
        if (hasErrors) {
            return;
        }
        
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="loading-spinner"></span>Connecting...';
        submitBtn.style.position = 'relative';
        
        try {
            const formData = new FormData(form);
            const data = Object.fromEntries(formData);
            delete data.terms;
            
            const response = await fetch('/auth/register', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data)
            });
            
            const result = await response.json();
            
            if (response.ok && result.success) {
                window.location.href = result.redirect || '/welcome';
            } else {
                if (result.errors && Array.isArray(result.errors)) {
                    result.errors.forEach(error => {
                        if (error.path && errors[error.path]) {
                            showError(error.path, error.msg);
                        }
                    });
                } else {
                    alert(result.message || 'Registration failed. Please try again.');
                }
                submitBtn.disabled = false;
                submitBtn.innerHTML = 'Connect to WiFi';
            }
        } catch (error) {
            console.error('Registration error:', error);
            alert('Network error. Please try again.');
            submitBtn.disabled = false;
            submitBtn.innerHTML = 'Connect to WiFi';
        }
    });
});